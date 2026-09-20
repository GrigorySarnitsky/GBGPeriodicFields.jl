# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-09-21 at commit `c843ce69` on Julia 1.12.7, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–**512³** both element types) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). **Two columns for since-retired cards were DROPPED on 2026-08-07** — both were measured under the `gcsample` regime of PERFORMANCE.md §4(s), which inflated device rows 2–29×, and neither card is in the fleet to re-sweep, so those columns could never be corrected or compared against anything measured after the fix. Every remaining column is measured at the decision-38/39 rewrite. **Both GPU columns are now in the fixed measurement regime and are comparable again.** Device lanes used to run with a blanket `gcsample = true`, so a full `GC.gc()` — whose finalizers free device buffers and synchronize — preceded every sample and dominated operations lasting tens of microseconds, inflating device rows 18.4–29.2× at ``64^3``, 5.8–19.8× at ``128^3`` and 1.9–4.25× at ``256^3`` on the AMD card. `gcsample` is now decided per row from a measured device-pool probe and kept only for rows that genuinely materialize. **GPU 7900XTX was re-swept 2026-08-07** (median −81.6%) and **GPU 5070TI on 2026-08-09** (median −46.4% over 426 rows). The NVIDIA correction is the smaller of the two because that vendor's collect-and-synchronize is cheaper, not because less was wrong: the CUDA branch of the probe called `CUDA.available_memory`, which is not a binding, so it threw on every row and the catch-all held every CUDA row on the collector until 2026-08-09 — see PERFORMANCE.md §4(w), and note that a fallback reported as a measurement is the reason that went unnoticed. CPU columns were never affected, `gcsample` being gated on the backend. See PERFORMANCE.md §4(s). **`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and at the larger grids the shift does not reproduce:** across that host's 192 `fft` rows (four lanes × 48) against its 2026-07-22 archive, exactly **one** row at ``256^3`` moved slower and by +1.0%, where `Enteropia` moved +38%; per-lane medians run −4.5% to −6.8%. Twenty-three rows did move slower, but all except that one sit at ``64^3``/``128^3``, and the three exceeding 20% are small-grid high-thread-count cells where thread overhead dominates a sub-millisecond workload. This host's rows moved materially *faster* at the larger grids (up to a ratio of 0.54), which is no better explained, so a cross-vintage `fft` comparison is uninformative rather than evidence. `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. **The 2026-08-09 `Enteropia` re-sweep settles it: the shift was a ONE-OFF, not a persistent state change.** Re-measuring t1/t2/t4 against the 2026-08-05 archive over an interval with no source changes, the `fft` class is flat — per-lane medians −1.1% to −1.4%, and at ``256^3`` specifically −3.7%, −6.5% and −1.2%, where the event being explained was +20–50%. Every other class is flat too (600 rows per lane, overall medians +0.0%, −0.2%, −0.2%), so the sweep reproduces itself and the instrument is sound. Those three lanes are also the first archives carrying stamped platform state (kernel, microcode, governor, SMT, transparent huge pages), so a recurrence is now falsifiable instead of unattributable. See PERFORMANCE.md §4(p). **Five CPU rows are process-history-sensitive and comparable only against same-shaped sweeps — PERFORMANCE.md §4(y).** The two `materialize_kernel` rows, `lpnorm vec Inf`, `radial_correlation vec` and `cross-correlation vec.vec` measure faster at low thread counts inside a full sweep than standalone (up to ``3.2\times`` for `materialize_kernel` at ``t1``, ``1.2``–``1.7\times`` for the reductions three), because their per-call field-sized allocation lands in a regime selected by what streamed through the process before them; the eight allocating `fft` rows are verified clean. Every CPU column here is a full sweep, so the table is self-consistent, but those cells must not be compared against a standalone probe or a class-only lane, and `materialize_kernel` thread scaling should be read from ``t4`` upward (the ``t2`` cell of `materialize_kernel separable` is bistable across sweeps). **The `CPU 9800X3D t8` column was assembled from FOUR per-grid runs, not one lane.** A single `-t8` process segfaults on `Enteropia` inside FFTW's threaded executor — PERFORMANCE.md §4(q), reproducible there and never seen on the other host — and failed three times running. Splitting the lane by grid (`CHAR_SIZES=64`, then 128, 256, 512) completes it: 64³, 256³ and 512³ passed first time and 128³ on its second attempt, and the four part-archives merge into one lane archive with disjoint rows, 150 per grid. That is what an uncrashed process would have written, and it is a harness workaround rather than a fix — the fault is unchanged and a plain `characterize.jl` invocation at `-t8` will still die here. The merged column is flat against the 2026-08-05 one it replaces (median +0.0% over 600 rows), and its largest movers are the `measure` twins, whose FFTW `MEASURE` plan search legitimately re-decides between runs. **Jitter at ``256^3`` is NOT bounded by the ~10% the paragraph above suggests, for the `Float32` gather rows.** `interpolate! trilinear`, `CatmullRom` and `Lalescu(3,3)` at ``256^3`` `Float32` move as a CORRELATED BLOCK between processes — all three the same direction within a run, by up to 31% — measured on the 9800X3D as ``0.73``/``0.82``/``0.86`` at `t1` and ``1.31``/``1.22``/``1.17`` at `t2` for the same code against the same archive. Direction varies by run, so it is per-process state rather than a systematic difference, but the standing advice to compare at ``256^3`` or above does not cover these three rows: read them across at least two sweeps. A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field.Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `84cd34aa @ 2026-09-04`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8, GPU 7900XTX; `c843ce69 @ 2026-09-20`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI. **Jitter is ~10% for most cells but NOT uniform: it reaches 1.44x at small grids under high thread counts.** Measured on the 12700K, `mean(norm) vec` `Float32`, five repeats of the same measurement: at ``64^3`` `-t8` the minimum came out 31.2, 31.0, 31.3, 30.8 and 44.4 us, where the same row at `-t1` spans 1.01x and at ``256^3`` `-t8` spans 1.09x. The work there (~31 us) is comparable to the cost of spawning eight threads, and taking BenchmarkTools' minimum over a one-second budget does not suppress it. So a movement of tens of percent in a small-grid, high-thread cell is NOT evidence of anything; compare those at ``256^3`` or above, or at low thread counts. PERFORMANCE.md §4(u).

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 3.918 ms | 2.714 ms | 2.355 ms | 2.195 ms | 2.712 ms | 1.531 ms | 843.917 μs | 559.325 μs | — | — |
| to_physical scalar measure | Float32 256^3 | 40.787 ms | 27.828 ms | 24.381 ms | 23.142 ms | 31.710 ms | 19.813 ms | 14.448 ms | 12.097 ms | — | — |
| to_physical scalar measure | Float32 512^3 | 518.930 ms | 415.058 ms | 266.003 ms | 236.036 ms | 312.455 ms | 188.298 ms | 147.969 ms | 129.424 ms | — | — |
| to_physical scalar measure | Float32 64^3 | 372.401 μs | 239.133 μs | 167.030 μs | 136.804 μs | 274.837 μs | 159.432 μs | 95.330 μs | 71.310 μs | — | — |
| to_physical scalar measure | Float64 128^3 | 6.074 ms | 5.447 ms | 5.263 ms | 4.635 ms | 3.824 ms | 2.206 ms | 1.467 ms | 1.162 ms | — | — |
| to_physical scalar measure | Float64 256^3 | 100.561 ms | 65.859 ms | 53.371 ms | 51.162 ms | 78.613 ms | 64.667 ms | 51.054 ms | 44.258 ms | — | — |
| to_physical scalar measure | Float64 512^3 | 1.109 s | 758.793 ms | 647.602 ms | 602.269 ms | 829.486 ms | 556.564 ms | 331.196 ms | 395.461 ms | — | — |
| to_physical scalar measure | Float64 64^3 | 552.097 μs | 330.769 μs | 248.346 μs | 239.370 μs | 360.079 μs | 211.243 μs | 126.840 μs | 94.230 μs | — | — |
| to_physical scalar | Float32 128^3 | 4.907 ms | 3.194 ms | 2.387 ms | 2.489 ms | 4.481 ms | 2.307 ms | 1.276 ms | 788.468 μs | 109.907 μs | 68.701 μs |
| to_physical scalar | Float32 256^3 | 88.659 ms | 51.334 ms | 35.026 ms | 26.894 ms | 168.483 ms | 88.262 ms | 48.571 ms | 28.200 ms | 1.023 ms | 1.098 ms |
| to_physical scalar | Float32 512^3 | 1.318 s | 805.427 ms | 510.403 ms | 310.947 ms | 1.948 s | 1.025 s | 561.965 ms | 326.235 ms | 13.707 ms | — |
| to_physical scalar | Float32 64^3 | 384.471 μs | 247.724 μs | 167.950 μs | 155.804 μs | 314.546 μs | 175.022 μs | 103.541 μs | 69.571 μs | 63.122 μs | 19.850 μs |
| to_physical scalar | Float64 128^3 | 7.964 ms | 5.763 ms | 4.826 ms | 4.459 ms | 9.940 ms | 5.221 ms | 3.119 ms | 1.979 ms | 287.085 μs | 432.524 μs |
| to_physical scalar | Float64 256^3 | 127.275 ms | 77.838 ms | 58.295 ms | 50.526 ms | 93.959 ms | 71.481 ms | 53.267 ms | 45.313 ms | 3.184 ms | 3.772 ms |
| to_physical scalar | Float64 512^3 | 1.452 s | 961.990 ms | 712.318 ms | 616.776 ms | 925.582 ms | 601.880 ms | 437.261 ms | 399.582 ms | — | — |
| to_physical scalar | Float64 64^3 | 674.464 μs | 406.860 μs | 287.362 μs | 270.478 μs | 525.313 μs | 287.183 μs | 167.140 μs | 115.171 μs | 94.651 μs | 51.720 μs |
| to_physical vector measure | Float32 128^3 | 11.438 ms | 8.690 ms | 7.341 ms | 5.698 ms | 9.420 ms | 5.437 ms | 3.638 ms | 2.898 ms | — | — |
| to_physical vector measure | Float32 256^3 | 201.767 ms | 126.468 ms | 88.118 ms | 111.194 ms | 104.933 ms | 62.827 ms | 45.455 ms | 38.373 ms | — | — |
| to_physical vector measure | Float32 512^3 | 1.855 s | 1.248 s | 990.574 ms | 930.481 ms | 1.135 s | 750.724 ms | 684.619 ms | 600.760 ms | — | — |
| to_physical vector measure | Float32 64^3 | 1.138 ms | 718.460 μs | 554.849 μs | 540.123 μs | 844.831 μs | 481.386 μs | 285.231 μs | 218.672 μs | — | — |
| to_physical vector measure | Float64 128^3 | 36.948 ms | 31.648 ms | 26.802 ms | 19.002 ms | 25.730 ms | 17.618 ms | 11.809 ms | 12.032 ms | — | — |
| to_physical vector measure | Float64 256^3 | 354.957 ms | 261.067 ms | 226.953 ms | 217.675 ms | 303.252 ms | 196.895 ms | 154.714 ms | 136.421 ms | — | — |
| to_physical vector measure | Float64 512^3 | 3.305 s | 2.288 s | 1.954 s | 1.822 s | 2.466 s | 1.667 s | 1.295 s | 1.156 s | — | — |
| to_physical vector measure | Float64 64^3 | 1.977 ms | 1.560 ms | 1.213 ms | 1.019 ms | 1.097 ms | 644.167 μs | 404.791 μs | 318.853 μs | — | — |
| to_physical vector | Float32 128^3 | 11.328 ms | 8.317 ms | 7.390 ms | 6.398 ms | 9.526 ms | 5.531 ms | 3.635 ms | 3.128 ms | 328.878 μs | 230.092 μs |
| to_physical vector | Float32 256^3 | 202.499 ms | 126.490 ms | 88.286 ms | 111.113 ms | 104.587 ms | 62.987 ms | 46.015 ms | 39.746 ms | 4.782 ms | 3.157 ms |
| to_physical vector | Float32 512^3 | 1.859 s | 1.246 s | 990.652 ms | 920.670 ms | 1.128 s | 763.641 ms | 676.397 ms | 597.655 ms | 55.475 ms | — |
| to_physical vector | Float32 64^3 | 1.137 ms | 711.582 μs | 517.997 μs | 518.713 μs | 845.961 μs | 472.066 μs | 284.602 μs | 219.222 μs | 102.124 μs | 45.160 μs |
| to_physical vector | Float64 128^3 | 36.878 ms | 30.607 ms | 27.018 ms | 18.629 ms | 26.117 ms | 17.669 ms | 11.806 ms | 12.367 ms | 978.819 μs | 1.354 ms |
| to_physical vector | Float64 256^3 | 355.242 ms | 260.258 ms | 225.147 ms | 216.074 ms | 297.017 ms | 197.309 ms | 157.602 ms | 134.194 ms | 13.143 ms | 11.390 ms |
| to_physical vector | Float64 512^3 | 3.303 s | 2.286 s | 1.956 s | 1.818 s | 2.493 s | 1.664 s | 1.295 s | 1.155 s | — | — |
| to_physical vector | Float64 64^3 | 1.942 ms | 1.235 ms | 1.131 ms | 1.047 ms | 1.112 ms | 684.797 μs | 405.390 μs | 306.442 μs | 201.711 μs | 144.451 μs |
| to_physical! scalar scratch | Float32 128^3 | 4.319 ms | 2.775 ms | 1.710 ms | 1.295 ms | 4.528 ms | 2.339 ms | 1.259 ms | 786.568 μs | 98.005 μs | 65.321 μs |
| to_physical! scalar scratch | Float32 256^3 | 87.514 ms | 50.357 ms | 34.032 ms | 26.671 ms | 163.612 ms | 87.486 ms | 47.711 ms | 25.787 ms | 800.392 μs | 1.029 ms |
| to_physical! scalar scratch | Float32 512^3 | 1.212 s | 666.404 ms | 399.497 ms | 287.211 ms | 1.920 s | 1.021 s | 552.502 ms | 323.956 ms | 10.410 ms | — |
| to_physical! scalar scratch | Float32 64^3 | 387.269 μs | 237.149 μs | 160.957 μs | 135.737 μs | 311.137 μs | 170.283 μs | 100.840 μs | 71.010 μs | 44.697 μs | 17.810 μs |
| to_physical! scalar scratch | Float64 128^3 | 7.569 ms | 4.995 ms | 3.969 ms | 3.525 ms | 9.774 ms | 5.103 ms | 2.758 ms | 1.586 ms | 261.508 μs | 428.194 μs |
| to_physical! scalar scratch | Float64 256^3 | 110.001 ms | 69.803 ms | 55.753 ms | 50.432 ms | 81.974 ms | 48.678 ms | 35.159 ms | 29.428 ms | 2.490 ms | 3.760 ms |
| to_physical! scalar scratch | Float64 512^3 | 1.115 s | 683.453 ms | 505.187 ms | 441.897 ms | 712.597 ms | 427.428 ms | 308.259 ms | 266.236 ms | — | — |
| to_physical! scalar scratch | Float64 64^3 | 658.970 μs | 393.844 μs | 276.115 μs | 237.625 μs | 523.053 μs | 288.544 μs | 168.260 μs | 121.901 μs | 71.194 μs | 49.720 μs |
| to_physical! scalar | Float32 128^3 | 3.964 ms | 2.167 ms | 1.220 ms | 746.371 μs | 4.821 ms | 2.221 ms | 1.126 ms | 630.576 μs | 86.754 μs | 58.950 μs |
| to_physical! scalar | Float32 256^3 | 83.317 ms | 46.246 ms | 29.619 ms | 22.648 ms | 161.713 ms | 82.481 ms | 43.071 ms | 22.764 ms | 625.905 μs | 852.949 μs |
| to_physical! scalar | Float32 512^3 | 1.181 s | 636.763 ms | 371.380 ms | 261.204 ms | 1.895 s | 994.201 ms | 525.984 ms | 297.921 ms | 8.988 ms | — |
| to_physical! scalar | Float32 64^3 | 355.770 μs | 204.846 μs | 122.039 μs | 89.025 μs | 299.457 μs | 155.052 μs | 85.520 μs | 53.660 μs | 40.729 μs | 15.990 μs |
| to_physical! scalar | Float64 128^3 | 6.178 ms | 3.689 ms | 2.571 ms | 1.980 ms | 9.514 ms | 4.851 ms | 2.511 ms | 1.351 ms | 241.243 μs | 398.424 μs |
| to_physical! scalar | Float64 256^3 | 102.156 ms | 62.437 ms | 47.968 ms | 43.002 ms | 73.696 ms | 39.661 ms | 26.443 ms | 20.075 ms | 2.157 ms | 3.409 ms |
| to_physical! scalar | Float64 512^3 | 1.058 s | 623.895 ms | 444.914 ms | 386.486 ms | 664.361 ms | 376.873 ms | 258.686 ms | 217.880 ms | — | — |
| to_physical! scalar | Float64 64^3 | 580.189 μs | 327.868 μs | 201.891 μs | 147.426 μs | 518.583 μs | 258.353 μs | 142.640 μs | 87.701 μs | 68.024 μs | 47.490 μs |
| to_physical! vector scratch | Float32 128^3 | 11.281 ms | 7.913 ms | 6.645 ms | 6.090 ms | 8.196 ms | 4.587 ms | 2.559 ms | 1.611 ms | 277.999 μs | 227.873 μs |
| to_physical! vector scratch | Float32 256^3 | 121.884 ms | 82.851 ms | 71.943 ms | 69.537 ms | 103.078 ms | 61.228 ms | 44.022 ms | 37.612 ms | 2.333 ms | 3.076 ms |
| to_physical! vector scratch | Float32 512^3 | 1.370 s | 872.062 ms | 700.371 ms | 648.995 ms | 928.170 ms | 585.911 ms | 441.477 ms | 382.799 ms | 28.880 ms | — |
| to_physical! vector scratch | Float32 64^3 | 1.134 ms | 685.101 μs | 462.505 μs | 389.456 μs | 844.990 μs | 463.616 μs | 277.242 μs | 225.672 μs | 80.688 μs | 42.181 μs |
| to_physical! vector scratch | Float64 128^3 | 18.786 ms | 16.201 ms | 16.212 ms | 14.417 ms | 13.914 ms | 9.925 ms | 5.784 ms | 4.288 ms | 817.459 μs | 1.351 ms |
| to_physical! vector scratch | Float64 256^3 | 242.345 ms | 170.045 ms | 154.983 ms | 149.289 ms | 188.371 ms | 127.629 ms | 98.137 ms | 85.366 ms | 7.524 ms | 11.291 ms |
| to_physical! vector scratch | Float64 512^3 | 2.219 s | 1.516 s | 1.320 s | 1.238 s | 1.733 s | 1.126 s | 872.432 ms | 767.185 ms | — | — |
| to_physical! vector scratch | Float64 64^3 | 1.663 ms | 1.008 ms | 736.922 μs | 645.643 μs | 1.089 ms | 622.777 μs | 385.180 μs | 294.472 μs | 189.753 μs | 141.621 μs |
| to_physical! vector | Float32 128^3 | 9.762 ms | 6.329 ms | 5.007 ms | 3.922 ms | 7.818 ms | 4.158 ms | 2.150 ms | 1.238 ms | 247.858 μs | 188.243 μs |
| to_physical! vector | Float32 256^3 | 110.444 ms | 71.466 ms | 60.793 ms | 58.428 ms | 92.231 ms | 52.499 ms | 34.698 ms | 27.126 ms | 1.824 ms | 2.549 ms |
| to_physical! vector | Float32 512^3 | 1.284 s | 780.400 ms | 612.590 ms | 559.012 ms | 858.124 ms | 517.637 ms | 372.095 ms | 313.890 ms | 24.807 ms | — |
| to_physical! vector | Float32 64^3 | 1.031 ms | 573.114 μs | 344.172 μs | 257.261 μs | 806.071 μs | 424.766 μs | 238.791 μs | 175.041 μs | 82.162 μs | 40.260 μs |
| to_physical! vector | Float64 128^3 | 16.039 ms | 13.039 ms | 13.184 ms | 11.525 ms | 12.619 ms | 7.560 ms | 4.064 ms | 2.446 ms | 728.504 μs | 1.218 ms |
| to_physical! vector | Float64 256^3 | 219.920 ms | 147.665 ms | 131.664 ms | 127.501 ms | 171.829 ms | 108.039 ms | 78.079 ms | 66.004 ms | 6.436 ms | 10.241 ms |
| to_physical! vector | Float64 512^3 | 2.049 s | 1.348 s | 1.150 s | 1.067 s | 1.583 s | 972.478 ms | 723.805 ms | 619.604 ms | — | — |
| to_physical! vector | Float64 64^3 | 1.427 ms | 759.497 μs | 496.185 μs | 393.014 μs | 1.004 ms | 545.106 μs | 308.261 μs | 202.412 μs | 169.631 μs | 137.182 μs |
| to_spectral scalar measure | Float32 128^3 | 3.333 ms | 2.233 ms | 1.852 ms | 1.178 ms | 2.700 ms | 1.426 ms | 794.957 μs | 473.555 μs | — | — |
| to_spectral scalar measure | Float32 256^3 | 35.062 ms | 23.865 ms | 19.458 ms | 18.319 ms | 34.488 ms | 20.278 ms | 12.823 ms | 10.048 ms | — | — |
| to_spectral scalar measure | Float32 512^3 | 475.660 ms | 373.303 ms | 239.272 ms | 208.051 ms | 310.838 ms | 172.507 ms | 116.442 ms | 99.066 ms | — | — |
| to_spectral scalar measure | Float32 64^3 | 358.002 μs | 211.899 μs | 143.962 μs | 110.840 μs | 272.927 μs | 146.952 μs | 84.221 μs | 62.001 μs | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.370 ms | 4.241 ms | 3.870 ms | 3.193 ms | 4.245 ms | 2.256 ms | 1.321 ms | 881.128 μs | — | — |
| to_spectral scalar measure | Float64 256^3 | 92.991 ms | 56.793 ms | 44.107 ms | 38.889 ms | 73.625 ms | 60.414 ms | 44.794 ms | 38.095 ms | — | — |
| to_spectral scalar measure | Float64 512^3 | 1.050 s | 702.841 ms | 566.930 ms | 517.095 ms | 762.996 ms | 487.461 ms | 349.589 ms | 325.603 ms | — | — |
| to_spectral scalar measure | Float64 64^3 | 497.941 μs | 290.946 μs | 211.217 μs | 186.327 μs | 347.369 μs | 189.292 μs | 112.381 μs | 81.701 μs | — | — |
| to_spectral scalar | Float32 128^3 | 4.334 ms | 2.716 ms | 1.978 ms | 1.502 ms | 4.341 ms | 2.265 ms | 1.300 ms | 730.127 μs | 68.598 μs | 40.681 μs |
| to_spectral scalar | Float32 256^3 | 86.001 ms | 48.526 ms | 29.120 ms | 22.112 ms | 165.415 ms | 85.590 ms | 46.824 ms | 26.343 ms | 688.794 μs | 682.148 μs |
| to_spectral scalar | Float32 512^3 | 1.284 s | 771.005 ms | 480.914 ms | 345.825 ms | 1.895 s | 973.377 ms | 514.739 ms | 288.722 ms | 9.542 ms | — |
| to_spectral scalar | Float32 64^3 | 365.817 μs | 214.691 μs | 153.119 μs | 110.601 μs | 304.467 μs | 165.992 μs | 92.271 μs | 59.340 μs | 51.582 μs | 14.560 μs |
| to_spectral scalar | Float64 128^3 | 7.094 ms | 5.059 ms | 4.138 ms | 3.380 ms | 10.269 ms | 5.466 ms | 2.960 ms | 1.711 ms | 236.989 μs | 380.474 μs |
| to_spectral scalar | Float64 256^3 | 141.209 ms | 80.312 ms | 53.117 ms | 47.281 ms | 189.968 ms | 115.196 ms | 71.602 ms | 51.850 ms | 2.581 ms | 3.061 ms |
| to_spectral scalar | Float64 512^3 | 1.650 s | 996.590 ms | 657.866 ms | 550.924 ms | 1.693 s | 956.365 ms | 557.807 ms | 424.416 ms | — | — |
| to_spectral scalar | Float64 64^3 | 674.857 μs | 350.652 μs | 214.929 μs | 212.164 μs | 504.453 μs | 274.013 μs | 154.230 μs | 95.710 μs | 77.780 μs | 45.540 μs |
| to_spectral vector measure | Float32 128^3 | 10.146 ms | 6.952 ms | 5.689 ms | 4.714 ms | 9.291 ms | 5.380 ms | 3.137 ms | 2.401 ms | — | — |
| to_spectral vector measure | Float32 256^3 | 183.803 ms | 98.448 ms | 67.770 ms | 93.801 ms | 101.440 ms | 59.267 ms | 39.631 ms | 30.437 ms | — | — |
| to_spectral vector measure | Float32 512^3 | 1.705 s | 1.117 s | 862.006 ms | 771.945 ms | 1.132 s | 667.792 ms | 588.250 ms | 495.948 ms | — | — |
| to_spectral vector measure | Float32 64^3 | 1.091 ms | 625.562 μs | 397.960 μs | 384.518 μs | 834.821 μs | 453.306 μs | 254.341 μs | 188.012 μs | — | — |
| to_spectral vector measure | Float64 128^3 | 34.025 ms | 25.277 ms | 21.979 ms | 16.017 ms | 26.716 ms | 16.983 ms | 10.747 ms | 11.798 ms | — | — |
| to_spectral vector measure | Float64 256^3 | 340.506 ms | 242.428 ms | 197.282 ms | 178.283 ms | 268.023 ms | 182.783 ms | 136.622 ms | 120.972 ms | — | — |
| to_spectral vector measure | Float64 512^3 | 3.162 s | 2.105 s | 1.695 s | 1.561 s | 2.277 s | 1.446 s | 1.097 s | 968.641 ms | — | — |
| to_spectral vector measure | Float64 64^3 | 1.620 ms | 1.043 ms | 817.617 μs | 739.979 μs | 1.039 ms | 581.266 μs | 345.700 μs | 247.452 μs | — | — |
| to_spectral vector | Float32 128^3 | 10.176 ms | 6.771 ms | 5.703 ms | 4.933 ms | 9.203 ms | 5.154 ms | 3.356 ms | 2.566 ms | 214.393 μs | 152.172 μs |
| to_spectral vector | Float32 256^3 | 182.844 ms | 98.822 ms | 66.499 ms | 95.495 ms | 100.616 ms | 59.295 ms | 40.074 ms | 30.998 ms | 2.852 ms | 2.101 ms |
| to_spectral vector | Float32 512^3 | 1.703 s | 1.113 s | 858.402 ms | 770.860 ms | 1.124 s | 675.826 ms | 587.785 ms | 496.067 ms | 44.808 ms | — |
| to_spectral vector | Float32 64^3 | 1.089 ms | 629.159 μs | 401.498 μs | 449.608 μs | 835.781 μs | 448.556 μs | 255.681 μs | 186.862 μs | 61.467 μs | 29.930 μs |
| to_spectral vector | Float64 128^3 | 34.651 ms | 25.479 ms | 21.547 ms | 14.343 ms | 26.894 ms | 17.197 ms | 11.481 ms | 11.360 ms | 757.621 μs | 1.162 ms |
| to_spectral vector | Float64 256^3 | 339.611 ms | 242.025 ms | 199.458 ms | 179.282 ms | 263.406 ms | 181.576 ms | 136.937 ms | 116.392 ms | 11.470 ms | 9.230 ms |
| to_spectral vector | Float64 512^3 | 3.155 s | 2.115 s | 1.704 s | 1.566 s | 2.263 s | 1.451 s | 1.104 s | 986.126 ms | — | — |
| to_spectral vector | Float64 64^3 | 1.598 ms | 1.058 ms | 1.057 ms | 760.270 μs | 1.038 ms | 585.247 μs | 349.420 μs | 250.102 μs | 180.596 μs | 126.321 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 394.768 μs | 241.694 μs | 172.350 μs | 76.417 μs | 162.412 μs | 84.671 μs | 44.230 μs | 35.600 μs | 59.397 μs | 34.191 μs |
| add! scalar | Float32 256^3 | 8.151 ms | 7.354 ms | 5.632 ms | 5.172 ms | 3.502 ms | 3.027 ms | 2.743 ms | 2.808 ms | 345.049 μs | 275.633 μs |
| add! scalar | Float32 512^3 | 68.219 ms | 62.765 ms | 48.666 ms | 45.603 ms | 41.657 ms | 36.802 ms | 36.631 ms | 37.311 ms | 2.562 ms | — |
| add! scalar | Float32 64^3 | 42.302 μs | 20.924 μs | 9.892 μs | 10.125 μs | 22.479 μs | 12.320 μs | 6.637 μs | 6.695 μs | 31.189 μs | 10.080 μs |
| add! scalar | Float64 128^3 | 1.461 ms | 1.282 ms | 945.520 μs | 803.412 μs | 324.201 μs | 168.883 μs | 88.350 μs | 72.781 μs | 60.389 μs | 38.021 μs |
| add! scalar | Float64 256^3 | 16.662 ms | 15.274 ms | 11.809 ms | 11.014 ms | 9.932 ms | 8.683 ms | 8.435 ms | 8.750 ms | 534.412 μs | 511.406 μs |
| add! scalar | Float64 512^3 | 135.906 ms | 123.786 ms | 97.631 ms | 91.228 ms | 79.006 ms | 70.026 ms | 73.395 ms | 73.986 ms | — | — |
| add! scalar | Float64 64^3 | 83.709 μs | 49.523 μs | 20.896 μs | 12.218 μs | 41.561 μs | 24.260 μs | 12.100 μs | 9.340 μs | 31.898 μs | 10.110 μs |
| combine! vec | Float32 128^3 | 2.594 ms | 2.393 ms | 1.802 ms | 1.589 ms | 628.017 μs | 304.825 μs | 165.091 μs | 116.191 μs | 189.099 μs | 132.011 μs |
| combine! vec | Float32 256^3 | 25.266 ms | 23.207 ms | 18.280 ms | 16.899 ms | 13.777 ms | 14.066 ms | 13.810 ms | 13.821 ms | 1.334 ms | 966.301 μs |
| combine! vec | Float32 512^3 | 199.716 ms | 183.841 ms | 149.155 ms | 137.937 ms | 113.019 ms | 107.622 ms | 110.503 ms | 111.882 ms | 11.393 ms | — |
| combine! vec | Float32 64^3 | 127.298 μs | 69.076 μs | 40.129 μs | 23.645 μs | 65.570 μs | 35.931 μs | 20.580 μs | 14.910 μs | 46.454 μs | 22.190 μs |
| combine! vec | Float64 128^3 | 5.883 ms | 5.416 ms | 4.113 ms | 3.726 ms | 2.250 ms | 1.812 ms | 1.615 ms | 1.486 ms | 236.122 μs | 193.562 μs |
| combine! vec | Float64 256^3 | 47.105 ms | 46.765 ms | 36.661 ms | 34.203 ms | 27.815 ms | 26.621 ms | 26.912 ms | 27.307 ms | 1.691 ms | 1.532 ms |
| combine! vec | Float64 512^3 | 408.479 ms | 372.299 ms | 294.881 ms | 274.458 ms | 233.970 ms | 217.580 ms | 221.023 ms | 220.746 ms | — | — |
| combine! vec | Float64 64^3 | 264.849 μs | 150.197 μs | 76.214 μs | 45.340 μs | 123.513 μs | 64.800 μs | 35.060 μs | 25.800 μs | 48.839 μs | 22.161 μs |
| cross! | Float32 128^3 | 2.720 ms | 2.487 ms | 2.109 ms | 1.970 ms | 1.984 ms | 989.296 μs | 497.345 μs | 247.032 μs | 52.034 μs | 86.411 μs |
| cross! | Float32 256^3 | 27.416 ms | 25.121 ms | 23.436 ms | 22.340 ms | 23.276 ms | 14.738 ms | 12.530 ms | 12.470 ms | 863.742 μs | 771.678 μs |
| cross! | Float32 512^3 | 214.072 ms | 198.194 ms | 193.490 ms | 185.004 ms | 186.318 ms | 118.224 ms | 110.891 ms | 112.427 ms | 7.279 ms | — |
| cross! | Float32 64^3 | 246.702 μs | 128.695 μs | 71.534 μs | 38.146 μs | 228.968 μs | 114.761 μs | 58.960 μs | 31.800 μs | 36.223 μs | 9.240 μs |
| cross! | Float64 128^3 | 6.274 ms | 5.649 ms | 5.109 ms | 4.874 ms | 3.780 ms | 2.246 ms | 1.602 ms | 1.473 ms | 234.140 μs | 196.833 μs |
| cross! | Float64 256^3 | 48.709 ms | 50.835 ms | 47.889 ms | 45.256 ms | 40.109 ms | 29.060 ms | 27.011 ms | 27.456 ms | 1.628 ms | 1.536 ms |
| cross! | Float64 512^3 | 406.884 ms | 403.297 ms | 385.082 ms | 368.655 ms | 305.885 ms | 226.046 ms | 221.573 ms | 223.666 ms | — | — |
| cross! | Float64 64^3 | 360.048 μs | 188.619 μs | 95.905 μs | 54.238 μs | 227.406 μs | 115.441 μs | 58.820 μs | 36.680 μs | 41.287 μs | 14.470 μs |
| det! tensor | Float32 128^3 | 3.245 ms | 2.475 ms | 2.005 ms | 1.795 ms | 2.214 ms | 1.209 ms | 550.885 μs | 294.333 μs | 74.505 μs | 102.231 μs |
| det! tensor | Float32 256^3 | 34.829 ms | 26.684 ms | 22.230 ms | 19.169 ms | 24.567 ms | 17.128 ms | 11.955 ms | 11.935 ms | 924.348 μs | 866.629 μs |
| det! tensor | Float32 512^3 | 269.696 ms | 205.446 ms | 180.708 ms | 164.431 ms | 213.180 ms | 124.422 ms | 104.057 ms | 104.050 ms | 7.751 ms | — |
| det! tensor | Float32 64^3 | 305.379 μs | 155.974 μs | 82.421 μs | 46.381 μs | 250.627 μs | 133.092 μs | 65.810 μs | 36.241 μs | 41.720 μs | 10.740 μs |
| det! tensor | Float64 128^3 | 6.788 ms | 5.509 ms | 4.741 ms | 4.140 ms | 4.125 ms | 2.523 ms | 1.679 ms | 1.614 ms | 256.242 μs | 194.883 μs |
| det! tensor | Float64 256^3 | 50.686 ms | 48.346 ms | 42.893 ms | 39.713 ms | 41.917 ms | 25.056 ms | 24.934 ms | 25.718 ms | 1.773 ms | 1.685 ms |
| det! tensor | Float64 512^3 | 374.619 ms | 399.163 ms | 340.632 ms | 316.102 ms | 398.690 ms | 242.622 ms | 205.694 ms | 210.740 ms | — | — |
| det! tensor | Float64 64^3 | 351.752 μs | 187.150 μs | 110.118 μs | 63.817 μs | 261.537 μs | 129.382 μs | 78.980 μs | 42.510 μs | 43.371 μs | 16.160 μs |
| dot! vec.vec | Float32 128^3 | 2.740 ms | 1.671 ms | 1.262 ms | 1.102 ms | 2.451 ms | 1.240 ms | 623.595 μs | 321.143 μs | 85.003 μs | 69.280 μs |
| dot! vec.vec | Float32 256^3 | 24.149 ms | 17.264 ms | 15.421 ms | 13.925 ms | 23.398 ms | 11.520 ms | 8.119 ms | 8.045 ms | 684.643 μs | 582.636 μs |
| dot! vec.vec | Float32 512^3 | 202.410 ms | 136.894 ms | 126.265 ms | 114.990 ms | 195.534 ms | 86.263 ms | 75.503 ms | 75.739 ms | 5.421 ms | — |
| dot! vec.vec | Float32 64^3 | 329.659 μs | 199.082 μs | 104.985 μs | 59.178 μs | 311.327 μs | 162.092 μs | 81.760 μs | 44.331 μs | 34.981 μs | 13.430 μs |
| dot! vec.vec | Float64 128^3 | 4.235 ms | 3.768 ms | 3.151 ms | 2.803 ms | 3.806 ms | 1.708 ms | 966.067 μs | 590.945 μs | 177.146 μs | 133.882 μs |
| dot! vec.vec | Float64 256^3 | 37.273 ms | 35.125 ms | 29.203 ms | 27.052 ms | 33.349 ms | 19.491 ms | 17.864 ms | 19.015 ms | 1.224 ms | 1.147 ms |
| dot! vec.vec | Float64 512^3 | 288.057 ms | 275.061 ms | 234.425 ms | 216.575 ms | 217.893 ms | 150.784 ms | 149.449 ms | 150.702 ms | — | — |
| dot! vec.vec | Float64 64^3 | 337.903 μs | 213.034 μs | 106.815 μs | 63.950 μs | 323.088 μs | 161.222 μs | 82.771 μs | 44.780 μs | 34.808 μs | 13.640 μs |
| map!(+) vec | Float32 128^3 | 2.741 ms | 2.463 ms | 2.127 ms | 1.965 ms | 1.742 ms | 825.883 μs | 416.724 μs | 210.292 μs | 52.143 μs | 78.411 μs |
| map!(+) vec | Float32 256^3 | 27.236 ms | 25.048 ms | 23.395 ms | 22.340 ms | 21.821 ms | 14.251 ms | 12.597 ms | 12.462 ms | 865.368 μs | 771.908 μs |
| map!(+) vec | Float32 512^3 | 212.368 ms | 198.161 ms | 192.453 ms | 184.242 ms | 168.884 ms | 116.756 ms | 110.793 ms | 112.206 ms | 7.307 ms | — |
| map!(+) vec | Float32 64^3 | 241.663 μs | 128.393 μs | 71.643 μs | 37.873 μs | 199.588 μs | 93.411 μs | 47.850 μs | 26.930 μs | 35.407 μs | 9.250 μs |
| map!(+) vec | Float64 128^3 | 6.210 ms | 5.685 ms | 5.069 ms | 4.879 ms | 3.723 ms | 2.232 ms | 1.590 ms | 1.474 ms | 229.661 μs | 196.953 μs |
| map!(+) vec | Float64 256^3 | 48.534 ms | 50.678 ms | 47.661 ms | 45.511 ms | 35.169 ms | 28.847 ms | 27.119 ms | 27.471 ms | 1.605 ms | 1.539 ms |
| map!(+) vec | Float64 512^3 | 404.152 ms | 402.276 ms | 382.914 ms | 368.224 ms | 294.123 ms | 223.038 ms | 220.363 ms | 222.436 ms | — | — |
| map!(+) vec | Float64 64^3 | 349.556 μs | 188.333 μs | 98.811 μs | 54.632 μs | 204.375 μs | 94.911 μs | 48.330 μs | 33.010 μs | 39.557 μs | 12.270 μs |
| map!(det) tensor | Float32 128^3 | 3.227 ms | 2.473 ms | 1.987 ms | 1.781 ms | 2.170 ms | 1.190 ms | 546.765 μs | 292.413 μs | 74.914 μs | 102.091 μs |
| map!(det) tensor | Float32 256^3 | 34.801 ms | 26.725 ms | 22.041 ms | 19.134 ms | 24.644 ms | 17.112 ms | 11.972 ms | 11.948 ms | 923.472 μs | 835.789 μs |
| map!(det) tensor | Float32 512^3 | 269.600 ms | 205.517 ms | 179.268 ms | 163.133 ms | 216.048 ms | 123.684 ms | 103.667 ms | 103.897 ms | 7.815 ms | — |
| map!(det) tensor | Float32 64^3 | 300.234 μs | 152.070 μs | 81.456 μs | 48.385 μs | 249.708 μs | 130.851 μs | 65.300 μs | 35.991 μs | 41.331 μs | 10.840 μs |
| map!(det) tensor | Float64 128^3 | 6.784 ms | 5.586 ms | 4.759 ms | 4.137 ms | 4.101 ms | 2.496 ms | 1.669 ms | 1.612 ms | 254.510 μs | 194.992 μs |
| map!(det) tensor | Float64 256^3 | 50.709 ms | 48.427 ms | 42.876 ms | 39.719 ms | 41.926 ms | 25.057 ms | 25.024 ms | 25.626 ms | 1.755 ms | 1.697 ms |
| map!(det) tensor | Float64 512^3 | 373.186 ms | 399.393 ms | 341.073 ms | 317.422 ms | 411.528 ms | 235.702 ms | 205.973 ms | 210.259 ms | — | — |
| map!(det) tensor | Float64 64^3 | 348.776 μs | 186.642 μs | 106.469 μs | 59.339 μs | 260.706 μs | 128.942 μs | 65.750 μs | 41.600 μs | 42.507 μs | 16.190 μs |
| mul! tensor.vec | Float32 128^3 | 4.689 ms | 4.256 ms | 3.781 ms | 3.553 ms | 3.203 ms | 1.900 ms | 993.899 μs | 806.387 μs | 214.159 μs | 152.882 μs |
| mul! tensor.vec | Float32 256^3 | 53.208 ms | 41.247 ms | 37.525 ms | 34.583 ms | 32.077 ms | 28.098 ms | 22.905 ms | 21.204 ms | 1.446 ms | 1.254 ms |
| mul! tensor.vec | Float32 512^3 | 411.912 ms | 322.148 ms | 305.492 ms | 286.379 ms | 345.937 ms | 214.565 ms | 175.489 ms | 176.276 ms | 11.876 ms | — |
| mul! tensor.vec | Float32 64^3 | 464.734 μs | 229.217 μs | 121.734 μs | 73.626 μs | 372.727 μs | 212.322 μs | 107.120 μs | 72.340 μs | 47.308 μs | 12.750 μs |
| mul! tensor.vec | Float64 128^3 | 10.976 ms | 9.235 ms | 9.276 ms | 8.019 ms | 6.950 ms | 5.542 ms | 4.292 ms | 4.240 ms | 392.904 μs | 318.084 μs |
| mul! tensor.vec | Float64 256^3 | 78.463 ms | 78.742 ms | 74.593 ms | 70.686 ms | 59.742 ms | 46.717 ms | 43.761 ms | 43.607 ms | 2.808 ms | 2.513 ms |
| mul! tensor.vec | Float64 512^3 | 620.002 ms | 639.205 ms | 595.716 ms | 566.782 ms | 595.482 ms | 386.120 ms | 344.854 ms | 349.974 ms | — | — |
| mul! tensor.vec | Float64 64^3 | 691.553 μs | 450.545 μs | 352.251 μs | 215.068 μs | 377.250 μs | 215.513 μs | 109.480 μs | 59.430 μs | 46.245 μs | 18.430 μs |
| norm! vec | Float32 128^3 | 727.052 μs | 595.821 μs | 472.882 μs | 349.322 μs | 216.682 μs | 116.002 μs | 64.271 μs | 54.150 μs | 66.987 μs | 39.410 μs |
| norm! vec | Float32 256^3 | 10.265 ms | 9.491 ms | 7.857 ms | 7.329 ms | 4.778 ms | 4.370 ms | 4.113 ms | 4.248 ms | 432.178 μs | 338.233 μs |
| norm! vec | Float32 512^3 | 79.706 ms | 79.082 ms | 66.803 ms | 62.751 ms | 48.472 ms | 45.297 ms | 46.103 ms | 46.802 ms | 3.454 ms | — |
| norm! vec | Float32 64^3 | 53.459 μs | 37.584 μs | 18.899 μs | 16.396 μs | 30.630 μs | 20.281 μs | 12.760 μs | 11.340 μs | 32.593 μs | 11.020 μs |
| norm! vec | Float64 128^3 | 2.096 ms | 1.913 ms | 1.473 ms | 1.330 ms | 468.922 μs | 244.894 μs | 128.991 μs | 102.261 μs | 134.313 μs | 79.961 μs |
| norm! vec | Float64 256^3 | 21.312 ms | 19.852 ms | 16.262 ms | 15.109 ms | 11.128 ms | 10.277 ms | 10.244 ms | 10.544 ms | 916.596 μs | 671.217 μs |
| norm! vec | Float64 512^3 | 172.936 ms | 156.727 ms | 132.872 ms | 125.190 ms | 96.735 ms | 88.503 ms | 92.426 ms | 92.431 ms | — | — |
| norm! vec | Float64 64^3 | 157.680 μs | 89.235 μs | 50.074 μs | 31.397 μs | 56.622 μs | 36.360 μs | 21.110 μs | 16.560 μs | 41.177 μs | 16.590 μs |
| tr! tensor | Float32 128^3 | 734.483 μs | 559.301 μs | 430.532 μs | 335.228 μs | 213.993 μs | 112.712 μs | 60.510 μs | 51.211 μs | 65.701 μs | 39.191 μs |
| tr! tensor | Float32 256^3 | 10.244 ms | 9.450 ms | 7.650 ms | 7.084 ms | 4.718 ms | 4.341 ms | 4.267 ms | 4.351 ms | 437.144 μs | 335.914 μs |
| tr! tensor | Float32 512^3 | 79.574 ms | 77.635 ms | 65.168 ms | 60.970 ms | 47.369 ms | 45.489 ms | 46.139 ms | 46.943 ms | 3.459 ms | — |
| tr! tensor | Float32 64^3 | 52.453 μs | 33.802 μs | 15.555 μs | 14.256 μs | 27.330 μs | 18.090 μs | 10.850 μs | 9.180 μs | 32.527 μs | 10.780 μs |
| tr! tensor | Float64 128^3 | 2.103 ms | 1.853 ms | 1.430 ms | 1.286 ms | 491.552 μs | 240.863 μs | 125.671 μs | 99.391 μs | 71.183 μs | 71.041 μs |
| tr! tensor | Float64 256^3 | 19.755 ms | 19.194 ms | 15.903 ms | 14.845 ms | 11.384 ms | 10.377 ms | 10.471 ms | 10.716 ms | 719.948 μs | 671.357 μs |
| tr! tensor | Float64 512^3 | 156.280 ms | 155.233 ms | 131.168 ms | 121.900 ms | 101.971 ms | 92.454 ms | 92.758 ms | 94.202 ms | — | — |
| tr! tensor | Float64 64^3 | 104.864 μs | 63.597 μs | 33.899 μs | 23.482 μs | 53.231 μs | 31.500 μs | 19.030 μs | 14.620 μs | 33.635 μs | 11.040 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.576 ms | 2.823 ms | 1.538 ms | 1.196 ms | 3.220 ms | 1.653 ms | 835.547 μs | 426.074 μs | 54.837 μs | 32.620 μs |
| curl! vec->vec | Float32 256^3 | 44.148 ms | 22.919 ms | 17.301 ms | 16.534 ms | 26.074 ms | 13.184 ms | 8.562 ms | 8.753 ms | 588.036 μs | 542.146 μs |
| curl! vec->vec | Float32 512^3 | 353.315 ms | 179.508 ms | 143.990 ms | 137.294 ms | 207.545 ms | 105.282 ms | 82.595 ms | 83.637 ms | 4.680 ms | — |
| curl! vec->vec | Float32 64^3 | 705.825 μs | 359.143 μs | 183.677 μs | 98.611 μs | 417.577 μs | 221.333 μs | 111.631 μs | 60.220 μs | 36.793 μs | 12.040 μs |
| curl! vec->vec | Float64 128^3 | 5.713 ms | 4.006 ms | 3.545 ms | 3.405 ms | 3.689 ms | 1.869 ms | 948.998 μs | 531.015 μs | 133.364 μs | 141.672 μs |
| curl! vec->vec | Float64 256^3 | 48.083 ms | 37.613 ms | 35.070 ms | 33.967 ms | 32.110 ms | 20.302 ms | 19.347 ms | 19.880 ms | 1.162 ms | 1.079 ms |
| curl! vec->vec | Float64 512^3 | 355.045 ms | 298.578 ms | 288.045 ms | 278.013 ms | 242.544 ms | 164.846 ms | 163.518 ms | 165.678 ms | — | — |
| curl! vec->vec | Float64 64^3 | 672.572 μs | 348.449 μs | 179.546 μs | 95.193 μs | 462.002 μs | 234.743 μs | 117.520 μs | 65.250 μs | 46.910 μs | 20.940 μs |
| divergence! vec->scalar | Float32 128^3 | 3.527 ms | 1.383 ms | 712.452 μs | 408.305 μs | 3.381 ms | 1.105 ms | 572.885 μs | 290.313 μs | 57.945 μs | 31.780 μs |
| divergence! vec->scalar | Float32 256^3 | 27.713 ms | 11.144 ms | 9.169 ms | 8.573 ms | 26.810 ms | 8.974 ms | 4.562 ms | 4.141 ms | 392.418 μs | 341.583 μs |
| divergence! vec->scalar | Float32 512^3 | 226.517 ms | 90.485 ms | 77.760 ms | 70.354 ms | 210.959 ms | 71.140 ms | 46.333 ms | 46.815 ms | 2.965 ms | — |
| divergence! vec->scalar | Float32 64^3 | 419.119 μs | 177.124 μs | 92.531 μs | 52.493 μs | 434.017 μs | 152.492 μs | 77.470 μs | 42.460 μs | 33.857 μs | 11.370 μs |
| divergence! vec->scalar | Float64 128^3 | 3.698 ms | 1.979 ms | 1.633 ms | 1.414 ms | 3.375 ms | 1.057 ms | 525.144 μs | 277.853 μs | 87.620 μs | 77.471 μs |
| divergence! vec->scalar | Float64 256^3 | 30.673 ms | 21.194 ms | 16.964 ms | 15.544 ms | 27.375 ms | 12.269 ms | 10.292 ms | 10.332 ms | 746.127 μs | 680.357 μs |
| divergence! vec->scalar | Float64 512^3 | 242.568 ms | 165.413 ms | 137.421 ms | 126.645 ms | 211.857 ms | 92.672 ms | 93.018 ms | 93.261 ms | — | — |
| divergence! vec->scalar | Float64 64^3 | 432.321 μs | 162.474 μs | 86.499 μs | 56.835 μs | 438.102 μs | 139.352 μs | 72.231 μs | 40.410 μs | 38.025 μs | 14.280 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 5.702 ms | 2.434 ms | 1.244 ms | 692.779 μs | 5.002 ms | 2.027 ms | 1.037 ms | 519.674 μs | 69.330 μs | 39.201 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 44.640 ms | 18.893 ms | 10.021 ms | 8.968 ms | 39.448 ms | 16.264 ms | 8.129 ms | 4.241 ms | 421.421 μs | 343.054 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | 358.158 ms | 149.536 ms | 84.462 ms | 75.408 ms | 311.204 ms | 128.753 ms | 64.528 ms | 46.958 ms | 3.433 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 726.125 μs | 319.160 μs | 163.816 μs | 90.956 μs | 635.815 μs | 272.493 μs | 138.330 μs | 74.161 μs | 36.197 μs | 13.341 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 5.822 ms | 2.460 ms | 1.740 ms | 1.436 ms | 4.924 ms | 1.992 ms | 997.737 μs | 508.074 μs | 107.350 μs | 77.541 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 46.563 ms | 21.865 ms | 17.488 ms | 15.830 ms | 39.993 ms | 15.874 ms | 10.339 ms | 10.278 ms | 773.989 μs | 682.247 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | 372.240 ms | 171.894 ms | 141.659 ms | 128.498 ms | 319.110 ms | 124.419 ms | 93.519 ms | 93.362 ms | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 695.916 μs | 304.124 μs | 159.747 μs | 89.859 μs | 649.537 μs | 262.303 μs | 131.390 μs | 71.020 μs | 42.792 μs | 18.291 μs |
| gradient! scalar->vec | Float32 128^3 | 3.186 ms | 1.663 ms | 860.037 μs | 523.230 μs | 1.937 ms | 975.658 μs | 493.494 μs | 252.472 μs | 45.290 μs | 27.630 μs |
| gradient! scalar->vec | Float32 256^3 | 25.611 ms | 14.266 ms | 13.060 ms | 12.654 ms | 15.621 ms | 7.811 ms | 5.674 ms | 5.655 ms | 454.539 μs | 376.464 μs |
| gradient! scalar->vec | Float32 512^3 | 199.885 ms | 117.273 ms | 111.807 ms | 107.941 ms | 124.519 ms | 65.000 ms | 63.645 ms | 64.215 ms | 3.440 ms | — |
| gradient! scalar->vec | Float32 64^3 | 400.236 μs | 222.293 μs | 108.992 μs | 59.583 μs | 248.198 μs | 126.602 μs | 64.430 μs | 35.160 μs | 34.679 μs | 10.560 μs |
| gradient! scalar->vec | Float64 128^3 | 3.286 ms | 2.726 ms | 2.445 ms | 2.312 ms | 2.045 ms | 993.885 μs | 496.744 μs | 253.173 μs | 96.994 μs | 97.121 μs |
| gradient! scalar->vec | Float64 256^3 | 30.343 ms | 28.512 ms | 27.158 ms | 26.222 ms | 20.117 ms | 14.843 ms | 14.023 ms | 14.114 ms | 903.390 μs | 750.508 μs |
| gradient! scalar->vec | Float64 512^3 | 234.131 ms | 231.614 ms | 222.220 ms | 216.104 ms | 156.371 ms | 129.432 ms | 127.291 ms | 127.975 ms | — | — |
| gradient! scalar->vec | Float64 64^3 | 348.222 μs | 179.004 μs | 98.332 μs | 59.368 μs | 256.456 μs | 125.882 μs | 64.040 μs | 34.840 μs | 41.213 μs | 16.570 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.374 ms | 2.291 ms | 1.397 ms | 1.196 ms | 3.392 ms | 1.684 ms | 850.948 μs | 436.174 μs | 56.988 μs | 34.440 μs |
| helmholtz! vec->vec | Float32 256^3 | 34.745 ms | 18.942 ms | 17.159 ms | 16.545 ms | 27.619 ms | 13.381 ms | 8.563 ms | 8.563 ms | 585.309 μs | 542.656 μs |
| helmholtz! vec->vec | Float32 512^3 | 272.622 ms | 152.243 ms | 143.418 ms | 137.564 ms | 216.841 ms | 108.866 ms | 82.454 ms | 83.786 ms | 4.648 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 550.689 μs | 284.112 μs | 145.572 μs | 79.303 μs | 452.257 μs | 230.983 μs | 116.850 μs | 61.420 μs | 37.518 μs | 12.210 μs |
| helmholtz! vec->vec | Float64 128^3 | 5.151 ms | 3.954 ms | 3.561 ms | 3.406 ms | 3.842 ms | 1.988 ms | 997.857 μs | 547.426 μs | 166.017 μs | 137.232 μs |
| helmholtz! vec->vec | Float64 256^3 | 44.785 ms | 37.406 ms | 35.231 ms | 33.842 ms | 33.262 ms | 20.399 ms | 19.371 ms | 19.568 ms | 1.199 ms | 1.074 ms |
| helmholtz! vec->vec | Float64 512^3 | 314.156 ms | 298.479 ms | 287.970 ms | 278.325 ms | 255.993 ms | 165.341 ms | 164.181 ms | 165.680 ms | — | — |
| helmholtz! vec->vec | Float64 64^3 | 594.686 μs | 300.358 μs | 154.333 μs | 86.174 μs | 509.304 μs | 259.773 μs | 129.480 μs | 71.451 μs | 53.498 μs | 27.280 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 7.577 ms | 3.843 ms | 1.972 ms | 1.209 ms | 6.317 ms | 3.168 ms | 1.589 ms | 803.277 μs | 65.597 μs | 39.900 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 60.390 ms | 30.946 ms | 17.514 ms | 16.672 ms | 50.226 ms | 25.069 ms | 12.618 ms | 8.544 ms | 583.095 μs | 542.916 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | 474.078 ms | 241.014 ms | 146.510 ms | 137.760 ms | 401.176 ms | 200.720 ms | 100.874 ms | 83.167 ms | 4.546 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 955.217 μs | 494.739 μs | 253.212 μs | 131.800 μs | 834.754 μs | 429.556 μs | 215.291 μs | 111.471 μs | 39.954 μs | 13.950 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 8.237 ms | 4.179 ms | 3.584 ms | 3.393 ms | 6.775 ms | 3.588 ms | 1.747 ms | 881.978 μs | 184.993 μs | 167.382 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 70.956 ms | 37.634 ms | 35.250 ms | 33.845 ms | 54.019 ms | 27.991 ms | 19.334 ms | 19.401 ms | 1.207 ms | 1.222 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | 511.003 ms | 301.233 ms | 288.076 ms | 277.913 ms | 434.841 ms | 234.821 ms | 165.339 ms | 165.269 ms | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 1.012 ms | 516.659 μs | 265.114 μs | 138.736 μs | 900.883 μs | 459.316 μs | 227.961 μs | 120.981 μs | 55.466 μs | 33.531 μs |
| inverse_curl! vec->vec | Float32 128^3 | 6.531 ms | 3.382 ms | 1.742 ms | 1.192 ms | 3.490 ms | 1.741 ms | 876.418 μs | 449.184 μs | 56.557 μs | 33.530 μs |
| inverse_curl! vec->vec | Float32 256^3 | 51.502 ms | 27.069 ms | 17.321 ms | 16.616 ms | 28.805 ms | 13.991 ms | 8.554 ms | 8.954 ms | 587.430 μs | 542.255 μs |
| inverse_curl! vec->vec | Float32 512^3 | 411.603 ms | 212.734 ms | 145.589 ms | 137.813 ms | 222.777 ms | 111.386 ms | 86.859 ms | 83.664 ms | 4.649 ms | — |
| inverse_curl! vec->vec | Float32 64^3 | 833.873 μs | 434.990 μs | 222.331 μs | 116.996 μs | 449.236 μs | 231.504 μs | 114.910 μs | 60.861 μs | 35.599 μs | 12.461 μs |
| inverse_curl! vec->vec | Float64 128^3 | 6.366 ms | 3.961 ms | 3.557 ms | 3.406 ms | 3.628 ms | 1.846 ms | 931.877 μs | 533.565 μs | 171.421 μs | 154.562 μs |
| inverse_curl! vec->vec | Float64 256^3 | 52.451 ms | 37.454 ms | 35.089 ms | 33.986 ms | 33.795 ms | 19.996 ms | 19.358 ms | 19.594 ms | 1.212 ms | 1.117 ms |
| inverse_curl! vec->vec | Float64 512^3 | 398.158 ms | 299.273 ms | 287.454 ms | 277.968 ms | 240.303 ms | 164.053 ms | 164.234 ms | 165.682 ms | — | — |
| inverse_curl! vec->vec | Float64 64^3 | 766.468 μs | 397.197 μs | 202.002 μs | 107.326 μs | 454.372 μs | 233.463 μs | 116.490 μs | 65.130 μs | 54.489 μs | 31.140 μs |
| inverse_laplacian! scalar | Float32 128^3 | 4.616 ms | 1.639 ms | 869.612 μs | 465.599 μs | 3.904 ms | 1.319 ms | 666.356 μs | 344.893 μs | 60.702 μs | 33.511 μs |
| inverse_laplacian! scalar | Float32 256^3 | 36.468 ms | 13.547 ms | 6.985 ms | 5.125 ms | 31.272 ms | 10.608 ms | 5.345 ms | 2.700 ms | 342.919 μs | 221.823 μs |
| inverse_laplacian! scalar | Float32 512^3 | 289.921 ms | 106.433 ms | 55.016 ms | 45.671 ms | 249.761 ms | 83.759 ms | 42.401 ms | 27.521 ms | 2.560 ms | — |
| inverse_laplacian! scalar | Float32 64^3 | 587.664 μs | 215.132 μs | 125.199 μs | 71.579 μs | 496.177 μs | 178.163 μs | 92.661 μs | 52.350 μs | 31.416 μs | 11.170 μs |
| inverse_laplacian! scalar | Float64 128^3 | 4.917 ms | 1.802 ms | 960.242 μs | 536.484 μs | 4.240 ms | 1.450 ms | 718.745 μs | 368.333 μs | 94.128 μs | 48.290 μs |
| inverse_laplacian! scalar | Float64 256^3 | 39.099 ms | 14.679 ms | 10.747 ms | 8.523 ms | 34.309 ms | 11.564 ms | 5.822 ms | 4.843 ms | 598.742 μs | 346.534 μs |
| inverse_laplacian! scalar | Float64 512^3 | 311.328 ms | 115.447 ms | 86.369 ms | 66.977 ms | 273.114 ms | 92.965 ms | 55.161 ms | 55.112 ms | — | — |
| inverse_laplacian! scalar | Float64 64^3 | 606.968 μs | 227.658 μs | 133.217 μs | 76.041 μs | 542.304 μs | 190.832 μs | 100.060 μs | 56.101 μs | 36.287 μs | 14.020 μs |
| laplacian! scalar | Float32 128^3 | 2.006 ms | 638.071 μs | 330.526 μs | 179.956 μs | 2.145 ms | 491.805 μs | 249.083 μs | 130.142 μs | 52.059 μs | 26.270 μs |
| laplacian! scalar | Float32 256^3 | 16.194 ms | 5.998 ms | 4.967 ms | 4.096 ms | 17.057 ms | 3.833 ms | 1.943 ms | 1.188 ms | 255.126 μs | 189.462 μs |
| laplacian! scalar | Float32 512^3 | 131.457 ms | 49.960 ms | 41.539 ms | 34.753 ms | 136.301 ms | 30.850 ms | 25.994 ms | 27.537 ms | 1.818 ms | — |
| laplacian! scalar | Float32 64^3 | 251.534 μs | 88.207 μs | 48.327 μs | 30.670 μs | 274.238 μs | 69.231 μs | 36.520 μs | 22.210 μs | 30.793 μs | 9.240 μs |
| laplacian! scalar | Float64 128^3 | 2.153 ms | 816.715 μs | 625.347 μs | 440.196 μs | 2.204 ms | 530.397 μs | 265.682 μs | 139.631 μs | 56.643 μs | 29.010 μs |
| laplacian! scalar | Float64 256^3 | 17.397 ms | 11.879 ms | 11.293 ms | 10.519 ms | 17.747 ms | 5.182 ms | 4.753 ms | 4.829 ms | 361.322 μs | 357.024 μs |
| laplacian! scalar | Float64 512^3 | 137.178 ms | 97.215 ms | 95.315 ms | 90.000 ms | 141.293 ms | 54.134 ms | 54.885 ms | 54.955 ms | — | — |
| laplacian! scalar | Float64 64^3 | 266.849 μs | 94.208 μs | 50.539 μs | 33.956 μs | 282.887 μs | 73.210 μs | 38.690 μs | 23.270 μs | 32.122 μs | 10.080 μs |
| reality_projection! scalar | Float32 128^3 | — | — | — | — | 62.190 μs | 35.599 μs | 18.390 μs | 11.670 μs | — | 9.511 μs |
| reality_projection! scalar | Float32 256^3 | — | — | — | — | 260.376 μs | 137.131 μs | 69.081 μs | 36.551 μs | — | 15.750 μs |
| reality_projection! scalar | Float32 512^3 | — | — | — | — | 1.032 ms | 541.777 μs | 269.891 μs | 138.922 μs | — | — |
| reality_projection! scalar | Float32 64^3 | — | — | — | — | 15.099 μs | 15.000 μs | 15.001 μs | 15.021 μs | — | 9.140 μs |
| reality_projection! scalar | Float64 128^3 | — | — | — | — | 59.770 μs | 32.141 μs | 16.910 μs | 10.640 μs | — | 9.111 μs |
| reality_projection! scalar | Float64 256^3 | — | — | — | — | 255.174 μs | 134.630 μs | 65.921 μs | 34.361 μs | — | 14.920 μs |
| reality_projection! scalar | Float64 512^3 | — | — | — | — | 1.089 ms | 538.155 μs | 261.843 μs | 136.922 μs | — | — |
| reality_projection! scalar | Float64 64^3 | — | — | — | — | 14.180 μs | 14.220 μs | 14.210 μs | 14.220 μs | — | 9.000 μs |
| reality_projection! vector | Float32 128^3 | — | — | — | — | 193.972 μs | 104.958 μs | 53.290 μs | 29.331 μs | — | 13.720 μs |
| reality_projection! vector | Float32 256^3 | — | — | — | — | 786.475 μs | 407.812 μs | 206.112 μs | 107.032 μs | — | 50.211 μs |
| reality_projection! vector | Float32 512^3 | — | — | — | — | 4.265 ms | 1.755 ms | 915.975 μs | 464.305 μs | — | — |
| reality_projection! vector | Float32 64^3 | — | — | — | — | 46.399 μs | 28.171 μs | 15.380 μs | 10.020 μs | — | 9.220 μs |
| reality_projection! vector | Float64 128^3 | — | — | — | — | 188.341 μs | 100.472 μs | 49.840 μs | 27.310 μs | — | 12.690 μs |
| reality_projection! vector | Float64 256^3 | — | — | — | — | 771.433 μs | 396.559 μs | 199.822 μs | 105.561 μs | — | 47.751 μs |
| reality_projection! vector | Float64 512^3 | — | — | — | — | 4.253 ms | 2.148 ms | 1.083 ms | 521.115 μs | — | — |
| reality_projection! vector | Float64 64^3 | — | — | — | — | 43.541 μs | 25.910 μs | 13.990 μs | 9.450 μs | — | 9.050 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.759 ms | 6.054 ms | 4.261 ms | 4.161 ms | 9.608 ms | 4.844 ms | 2.447 ms | 1.234 ms | 84.635 μs | 151.101 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 89.641 ms | 46.997 ms | 42.527 ms | 42.023 ms | 77.906 ms | 42.924 ms | 23.002 ms | 23.099 ms | 1.894 ms | 1.128 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | 733.400 ms | 382.725 ms | 346.421 ms | 334.824 ms | 631.693 ms | 329.567 ms | 200.032 ms | 197.829 ms | 14.546 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.466 ms | 741.265 μs | 375.621 μs | 201.462 μs | 1.214 ms | 621.529 μs | 313.211 μs | 159.511 μs | 44.361 μs | 18.670 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 13.174 ms | 10.926 ms | 9.482 ms | 9.473 ms | 10.506 ms | 5.713 ms | 4.027 ms | 3.761 ms | 462.875 μs | 285.714 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 111.993 ms | 89.767 ms | 85.834 ms | 84.383 ms | 89.279 ms | 55.767 ms | 48.630 ms | 49.750 ms | 3.417 ms | 2.210 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | 844.164 ms | 712.063 ms | 688.155 ms | 679.399 ms | 698.511 ms | 423.129 ms | 392.065 ms | 394.735 ms | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.511 ms | 814.580 μs | 420.871 μs | 221.147 μs | 1.279 ms | 647.218 μs | 324.751 μs | 168.281 μs | 55.850 μs | 32.720 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.111 μs | 1.183 μs | 1.124 μs | 1.118 μs | 1.165 μs | 1.168 μs | 1.175 μs | 1.173 μs | 80.434 μs | 25.780 μs |
| assignment_window | Float32 256^3 | 2.176 μs | 2.180 μs | 2.191 μs | 2.193 μs | 2.223 μs | 2.231 μs | 2.259 μs | 2.218 μs | 81.047 μs | 25.630 μs |
| assignment_window | Float32 512^3 | 4.432 μs | 4.707 μs | 4.430 μs | 4.435 μs | 4.457 μs | 4.456 μs | 4.479 μs | 4.479 μs | 74.238 μs | — |
| assignment_window | Float32 64^3 | 590.096 ns | 586.921 ns | 607.798 ns | 600.357 ns | 607.608 ns | 616.890 ns | 621.839 ns | 614.120 ns | 86.113 μs | 25.711 μs |
| assignment_window | Float64 128^3 | 1.438 μs | 1.587 μs | 1.439 μs | 1.459 μs | 1.544 μs | 1.561 μs | 1.565 μs | 1.563 μs | 77.699 μs | 26.980 μs |
| assignment_window | Float64 256^3 | 2.953 μs | 2.957 μs | 2.952 μs | 3.272 μs | 3.087 μs | 3.087 μs | 3.090 μs | 3.085 μs | 81.776 μs | 27.671 μs |
| assignment_window | Float64 512^3 | 5.689 μs | 5.701 μs | 5.703 μs | 5.797 μs | 5.990 μs | 5.966 μs | 5.984 μs | 5.982 μs | — | — |
| assignment_window | Float64 64^3 | 728.504 ns | 730.866 ns | 734.373 ns | 741.992 ns | 823.000 ns | 824.125 ns | 826.709 ns | 822.962 ns | 77.382 μs | 26.870 μs |
| combine!∘kernel vector | Float32 128^3 | 3.868 ms | 2.155 ms | 1.630 ms | 1.471 ms | 3.144 ms | 1.554 ms | 777.257 μs | 396.834 μs | 58.003 μs | 78.131 μs |
| combine!∘kernel vector | Float32 256^3 | 31.418 ms | 20.656 ms | 19.439 ms | 18.404 ms | 26.413 ms | 12.716 ms | 9.915 ms | 9.906 ms | 957.388 μs | 861.559 μs |
| combine!∘kernel vector | Float32 512^3 | 263.337 ms | 171.413 ms | 161.639 ms | 153.417 ms | 225.932 ms | 109.330 ms | 92.054 ms | 93.181 ms | 7.318 ms | — |
| combine!∘kernel vector | Float32 64^3 | 495.976 μs | 259.925 μs | 139.983 μs | 74.257 μs | 420.667 μs | 206.183 μs | 104.970 μs | 56.680 μs | 38.774 μs | 13.270 μs |
| combine!∘kernel vector | Float64 128^3 | 5.275 ms | 4.587 ms | 4.146 ms | 3.909 ms | 3.752 ms | 2.074 ms | 1.095 ms | 749.137 μs | 255.325 μs | 224.343 μs |
| combine!∘kernel vector | Float64 256^3 | 49.026 ms | 42.950 ms | 40.623 ms | 38.529 ms | 33.909 ms | 22.903 ms | 21.939 ms | 23.322 ms | 1.869 ms | 1.715 ms |
| combine!∘kernel vector | Float64 512^3 | 361.282 ms | 337.301 ms | 320.499 ms | 307.009 ms | 270.658 ms | 189.552 ms | 183.319 ms | 184.718 ms | — | — |
| combine!∘kernel vector | Float64 64^3 | 509.952 μs | 274.727 μs | 142.654 μs | 83.806 μs | 376.370 μs | 225.453 μs | 118.281 μs | 64.360 μs | 50.231 μs | 25.430 μs |
| convolve! scalar | Float32 128^3 | 1.589 ms | 300.612 μs | 198.800 μs | 88.466 μs | 919.832 μs | 108.539 μs | 55.421 μs | 37.541 μs | 41.907 μs | 21.430 μs |
| convolve! scalar | Float32 256^3 | 12.941 ms | 7.711 ms | 7.237 ms | 6.804 ms | 7.559 ms | 2.823 ms | 2.692 ms | 2.736 ms | 291.904 μs | 259.463 μs |
| convolve! scalar | Float32 512^3 | 105.016 ms | 65.359 ms | 63.431 ms | 59.542 ms | 61.057 ms | 37.143 ms | 36.521 ms | 37.164 ms | 2.052 ms | — |
| convolve! scalar | Float32 64^3 | 198.017 μs | 41.158 μs | 21.757 μs | 13.901 μs | 116.270 μs | 16.030 μs | 9.100 μs | 7.330 μs | 28.054 μs | 8.261 μs |
| convolve! scalar | Float64 128^3 | 1.762 ms | 1.355 ms | 1.156 ms | 1.019 ms | 1.032 ms | 175.533 μs | 90.451 μs | 75.351 μs | 57.715 μs | 34.020 μs |
| convolve! scalar | Float64 256^3 | 17.998 ms | 16.174 ms | 15.283 ms | 14.244 ms | 10.767 ms | 7.862 ms | 7.649 ms | 7.757 ms | 553.143 μs | 516.555 μs |
| convolve! scalar | Float64 512^3 | 142.058 ms | 131.762 ms | 125.751 ms | 118.876 ms | 120.455 ms | 73.761 ms | 73.757 ms | 74.130 ms | — | — |
| convolve! scalar | Float64 64^3 | 175.791 μs | 49.950 μs | 25.817 μs | 21.086 μs | 126.693 μs | 24.660 μs | 13.500 μs | 10.390 μs | 33.041 μs | 9.910 μs |
| convolve! vector | Float32 128^3 | 2.647 ms | 1.818 ms | 1.554 ms | 1.471 ms | 2.096 ms | 1.106 ms | 553.655 μs | 283.943 μs | 49.104 μs | 58.901 μs |
| convolve! vector | Float32 256^3 | 22.493 ms | 20.375 ms | 19.207 ms | 18.249 ms | 20.254 ms | 10.995 ms | 9.819 ms | 9.891 ms | 623.018 μs | 619.636 μs |
| convolve! vector | Float32 512^3 | 190.919 ms | 168.582 ms | 159.982 ms | 153.464 ms | 169.058 ms | 94.093 ms | 91.681 ms | 92.930 ms | 4.735 ms | — |
| convolve! vector | Float32 64^3 | 312.956 μs | 173.772 μs | 90.333 μs | 50.263 μs | 269.528 μs | 146.462 μs | 74.591 μs | 40.490 μs | 36.744 μs | 10.810 μs |
| convolve! vector | Float64 128^3 | 4.842 ms | 4.559 ms | 4.147 ms | 3.936 ms | 2.635 ms | 1.538 ms | 866.917 μs | 748.426 μs | 187.728 μs | 159.812 μs |
| convolve! vector | Float64 256^3 | 44.952 ms | 42.233 ms | 40.173 ms | 38.406 ms | 28.916 ms | 22.769 ms | 21.942 ms | 23.329 ms | 1.213 ms | 1.229 ms |
| convolve! vector | Float64 512^3 | 340.338 ms | 334.419 ms | 318.403 ms | 308.204 ms | 228.375 ms | 185.471 ms | 182.883 ms | 184.160 ms | — | — |
| convolve! vector | Float64 64^3 | 268.475 μs | 162.630 μs | 87.980 μs | 63.610 μs | 216.895 μs | 141.832 μs | 75.320 μs | 41.090 μs | 42.638 μs | 18.830 μs |
| convolve! vector ∘ radial    | Float32 128^3 | 4.110 ms | 2.145 ms | 1.473 ms | 1.230 ms | 2.448 ms | 1.234 ms | 627.195 μs | 320.003 μs | 127.777 μs | 82.451 μs |
| convolve! vector ∘ radial    | Float32 256^3 | 32.567 ms | 19.074 ms | 16.478 ms | 13.995 ms | 19.906 ms | 10.011 ms | 9.976 ms | 8.351 ms | 861.276 μs | 609.326 μs |
| convolve! vector ∘ radial    | Float32 512^3 | 260.725 ms | 153.055 ms | 126.764 ms | 106.445 ms | 157.818 ms | 86.295 ms | 80.659 ms | 82.398 ms | 6.548 ms | — |
| convolve! vector ∘ radial    | Float32 64^3 | 497.765 μs | 260.128 μs | 132.560 μs | 77.743 μs | 316.878 μs | 159.662 μs | 81.541 μs | 43.990 μs | 44.101 μs | 16.650 μs |
| convolve! vector ∘ radial    | Float64 128^3 | 5.103 ms | 4.101 ms | 3.508 ms | 2.949 ms | 2.859 ms | 1.456 ms | 726.685 μs | 410.253 μs | 149.936 μs | 137.482 μs |
| convolve! vector ∘ radial    | Float64 256^3 | 41.527 ms | 36.672 ms | 29.820 ms | 26.141 ms | 24.137 ms | 18.801 ms | 18.867 ms | 19.090 ms | 1.084 ms | 1.065 ms |
| convolve! vector ∘ radial    | Float64 512^3 | 329.321 ms | 290.663 ms | 225.546 ms | 199.280 ms | 193.078 ms | 161.149 ms | 161.983 ms | 164.050 ms | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | 533.590 μs | 278.916 μs | 142.231 μs | 88.343 μs | 343.199 μs | 180.123 μs | 91.120 μs | 49.240 μs | 46.540 μs | 18.490 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | 2.676 ms | 1.820 ms | 1.553 ms | 1.481 ms | 2.096 ms | 1.105 ms | 550.655 μs | 286.062 μs | 48.915 μs | 60.890 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | 23.272 ms | 20.388 ms | 19.238 ms | 18.286 ms | 19.809 ms | 10.937 ms | 9.795 ms | 9.870 ms | 623.028 μs | 617.537 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | 192.103 ms | 169.090 ms | 159.970 ms | 153.358 ms | 171.974 ms | 93.909 ms | 91.377 ms | 92.707 ms | 4.645 ms | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | 313.944 μs | 176.488 μs | 90.261 μs | 50.077 μs | 270.118 μs | 146.602 μs | 73.820 μs | 39.720 μs | 36.861 μs | 10.850 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | 4.881 ms | 4.565 ms | 4.088 ms | 3.913 ms | 2.616 ms | 1.542 ms | 882.218 μs | 743.127 μs | 179.090 μs | 159.322 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | 44.967 ms | 42.369 ms | 40.157 ms | 38.402 ms | 28.713 ms | 22.415 ms | 21.888 ms | 23.281 ms | 1.212 ms | 1.231 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | 342.881 ms | 334.479 ms | 319.558 ms | 308.139 ms | 227.936 ms | 184.792 ms | 182.410 ms | 183.564 ms | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | 271.151 μs | 166.509 μs | 88.254 μs | 58.057 μs | 217.896 μs | 140.862 μs | 75.450 μs | 40.621 μs | 42.660 μs | 18.771 μs |
| convolve! vector ∘ separable | Float32 128^3 | 6.741 ms | 3.449 ms | 1.776 ms | 1.200 ms | 4.637 ms | 2.328 ms | 1.175 ms | 591.756 μs | 125.778 μs | 83.061 μs |
| convolve! vector ∘ separable | Float32 256^3 | 53.348 ms | 27.340 ms | 16.981 ms | 13.330 ms | 37.222 ms | 18.627 ms | 9.377 ms | 8.428 ms | 850.028 μs | 614.277 μs |
| convolve! vector ∘ separable | Float32 512^3 | 423.606 ms | 221.217 ms | 137.072 ms | 107.433 ms | 296.324 ms | 148.608 ms | 82.176 ms | 82.632 ms | 6.745 ms | — |
| convolve! vector ∘ separable | Float32 64^3 | 853.568 μs | 435.299 μs | 223.806 μs | 118.335 μs | 591.027 μs | 298.135 μs | 150.421 μs | 77.871 μs | 44.128 μs | 16.750 μs |
| convolve! vector ∘ separable | Float64 128^3 | 6.730 ms | 4.084 ms | 3.388 ms | 2.462 ms | 3.937 ms | 1.981 ms | 999.328 μs | 512.775 μs | 246.534 μs | 144.892 μs |
| convolve! vector ∘ separable | Float64 256^3 | 53.933 ms | 36.967 ms | 29.232 ms | 23.130 ms | 33.072 ms | 20.716 ms | 19.061 ms | 19.283 ms | 1.685 ms | 1.078 ms |
| convolve! vector ∘ separable | Float64 512^3 | 431.280 ms | 292.886 ms | 230.767 ms | 186.772 ms | 260.961 ms | 159.636 ms | 163.738 ms | 164.420 ms | — | — |
| convolve! vector ∘ separable | Float64 64^3 | 816.311 μs | 426.235 μs | 220.551 μs | 114.761 μs | 490.203 μs | 249.493 μs | 126.310 μs | 67.060 μs | 58.106 μs | 25.520 μs |
| convolve! vector ∘ stored    | Float32 128^3 | 2.643 ms | 1.825 ms | 1.552 ms | 1.487 ms | 2.098 ms | 1.102 ms | 550.005 μs | 292.093 μs | 48.644 μs | 59.040 μs |
| convolve! vector ∘ stored    | Float32 256^3 | 23.216 ms | 20.411 ms | 19.232 ms | 18.265 ms | 20.301 ms | 10.938 ms | 9.794 ms | 9.884 ms | 620.710 μs | 619.686 μs |
| convolve! vector ∘ stored    | Float32 512^3 | 191.075 ms | 168.881 ms | 159.844 ms | 153.313 ms | 169.062 ms | 94.997 ms | 91.508 ms | 92.927 ms | 4.785 ms | — |
| convolve! vector ∘ stored    | Float32 64^3 | 313.061 μs | 176.906 μs | 92.055 μs | 50.540 μs | 270.238 μs | 146.442 μs | 74.061 μs | 40.630 μs | 37.027 μs | 10.830 μs |
| convolve! vector ∘ stored    | Float64 128^3 | 4.884 ms | 4.599 ms | 4.076 ms | 3.916 ms | 2.669 ms | 1.534 ms | 880.647 μs | 749.008 μs | 181.592 μs | 159.822 μs |
| convolve! vector ∘ stored    | Float64 256^3 | 45.015 ms | 42.347 ms | 40.188 ms | 38.434 ms | 28.690 ms | 22.809 ms | 21.928 ms | 22.067 ms | 1.214 ms | 1.233 ms |
| convolve! vector ∘ stored    | Float64 512^3 | 343.345 ms | 334.625 ms | 319.410 ms | 308.221 ms | 239.516 ms | 184.964 ms | 183.087 ms | 184.037 ms | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | 272.169 μs | 163.688 μs | 90.400 μs | 61.108 μs | 217.205 μs | 142.992 μs | 75.490 μs | 41.320 μs | 42.381 μs | 18.850 μs |
| exponential_convolve! scalar | Float32 128^3 | 6.107 ms | 2.697 ms | 1.360 ms | 727.276 μs | 5.020 ms | 2.113 ms | 1.062 ms | 540.795 μs | 49.958 μs | 26.590 μs |
| exponential_convolve! scalar | Float32 256^3 | 48.322 ms | 21.149 ms | 10.632 ms | 6.139 ms | 39.586 ms | 17.009 ms | 8.361 ms | 4.212 ms | 259.740 μs | 189.442 μs |
| exponential_convolve! scalar | Float32 512^3 | 383.996 ms | 167.866 ms | 84.733 ms | 49.804 ms | 316.359 ms | 131.248 ms | 67.977 ms | 34.843 ms | 1.853 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 763.831 μs | 349.404 μs | 179.776 μs | 101.066 μs | 645.047 μs | 279.684 μs | 144.180 μs | 78.011 μs | 31.203 μs | 9.460 μs |
| exponential_convolve! scalar | Float64 128^3 | 5.771 ms | 2.555 ms | 1.369 ms | 855.123 μs | 5.574 ms | 2.394 ms | 1.193 ms | 608.476 μs | 94.223 μs | 79.491 μs |
| exponential_convolve! scalar | Float64 256^3 | 45.741 ms | 20.253 ms | 11.999 ms | 10.926 ms | 43.958 ms | 18.840 ms | 9.536 ms | 4.996 ms | 602.281 μs | 565.716 μs |
| exponential_convolve! scalar | Float64 512^3 | 363.451 ms | 160.232 ms | 97.879 ms | 90.643 ms | 349.231 ms | 151.027 ms | 78.867 ms | 55.072 ms | — | — |
| exponential_convolve! scalar | Float64 64^3 | 718.522 μs | 329.227 μs | 171.598 μs | 96.254 μs | 698.528 μs | 322.674 μs | 158.820 μs | 85.171 μs | 40.426 μs | 17.380 μs |
| exponential_convolve! vector | Float32 128^3 | 5.381 ms | 2.624 ms | 1.502 ms | 1.221 ms | 4.711 ms | 1.858 ms | 944.538 μs | 475.104 μs | 47.339 μs | 33.410 μs |
| exponential_convolve! vector | Float32 256^3 | 43.128 ms | 22.920 ms | 17.686 ms | 16.394 ms | 44.728 ms | 16.140 ms | 10.086 ms | 8.988 ms | 557.247 μs | 538.166 μs |
| exponential_convolve! vector | Float32 512^3 | 341.219 ms | 192.776 ms | 145.958 ms | 135.677 ms | 448.065 ms | 146.524 ms | 93.780 ms | 83.312 ms | 4.150 ms | — |
| exponential_convolve! vector | Float32 64^3 | 678.353 μs | 320.987 μs | 163.749 μs | 88.537 μs | 629.686 μs | 250.604 μs | 126.511 μs | 67.281 μs | 34.994 μs | 9.980 μs |
| exponential_convolve! vector | Float64 128^3 | 5.870 ms | 4.010 ms | 3.573 ms | 3.358 ms | 5.238 ms | 2.065 ms | 1.046 ms | 550.585 μs | 97.710 μs | 142.372 μs |
| exponential_convolve! vector | Float64 256^3 | 50.211 ms | 37.296 ms | 35.338 ms | 33.608 ms | 70.016 ms | 25.246 ms | 20.834 ms | 20.110 ms | 1.161 ms | 1.076 ms |
| exponential_convolve! vector | Float64 512^3 | 367.007 ms | 294.295 ms | 282.292 ms | 269.246 ms | 1.005 s | 199.658 ms | 168.177 ms | 165.685 ms | — | — |
| exponential_convolve! vector | Float64 64^3 | 633.589 μs | 278.332 μs | 142.529 μs | 87.097 μs | 676.537 μs | 252.823 μs | 127.511 μs | 68.481 μs | 40.796 μs | 20.090 μs |
| inv separable | Float32 128^3 | 957.105 ns | 965.000 ns | 965.421 ns | 960.000 ns | 764.100 ns | 760.471 ns | 770.000 ns | 761.541 ns | 210.459 μs | 53.141 μs |
| inv separable | Float32 256^3 | 1.964 μs | 1.974 μs | 1.979 μs | 1.969 μs | 1.563 μs | 1.549 μs | 1.561 μs | 1.571 μs | 210.382 μs | 57.421 μs |
| inv separable | Float32 512^3 | 3.863 μs | 3.882 μs | 3.871 μs | 3.837 μs | 3.020 μs | 3.058 μs | 3.056 μs | 3.034 μs | 247.647 μs | — |
| inv separable | Float32 64^3 | 507.161 ns | 513.573 ns | 527.387 ns | 509.646 ns | 405.195 ns | 408.146 ns | 410.005 ns | 407.950 ns | 205.344 μs | 49.570 μs |
| inv separable | Float64 128^3 | 1.123 μs | 1.089 μs | 1.089 μs | 1.091 μs | 1.072 μs | 1.053 μs | 1.074 μs | 1.054 μs | 200.968 μs | 52.531 μs |
| inv separable | Float64 256^3 | 2.143 μs | 2.128 μs | 2.154 μs | 2.151 μs | 2.042 μs | 2.130 μs | 2.044 μs | 2.053 μs | 197.643 μs | 59.631 μs |
| inv separable | Float64 512^3 | 4.067 μs | 4.055 μs | 4.040 μs | 4.043 μs | 3.917 μs | 3.980 μs | 3.904 μs | 4.010 μs | — | — |
| inv separable | Float64 64^3 | 530.915 ns | 532.984 ns | 536.330 ns | 535.312 ns | 528.759 ns | 523.116 ns | 519.895 ns | 525.772 ns | 205.420 μs | 50.101 μs |
| materialize_kernel radial | Float32 128^3 | 1.436 ms | 605.672 μs | 404.875 μs | 220.775 μs | 1.131 ms | 351.666 μs | 178.701 μs | 92.851 μs | 53.151 μs | 25.960 μs |
| materialize_kernel radial | Float32 256^3 | 11.302 ms | 4.562 ms | 3.621 ms | 2.611 ms | 8.913 ms | 2.754 ms | 1.585 ms | 1.831 ms | 336.736 μs | 150.071 μs |
| materialize_kernel radial | Float32 512^3 | 89.600 ms | 35.943 ms | 28.688 ms | 22.224 ms | 71.376 ms | 22.538 ms | 30.439 ms | 17.827 ms | 5.278 ms | — |
| materialize_kernel radial | Float32 64^3 | 170.431 μs | 73.861 μs | 40.301 μs | 30.156 μs | 145.800 μs | 47.931 μs | 25.580 μs | 15.730 μs | 39.873 μs | 10.610 μs |
| materialize_kernel radial | Float64 128^3 | 1.492 ms | 968.027 μs | 693.167 μs | 442.106 μs | 1.178 ms | 374.176 μs | 235.522 μs | 281.403 μs | 61.949 μs | 29.561 μs |
| materialize_kernel radial | Float64 256^3 | 11.617 ms | 7.891 ms | 5.700 ms | 5.474 ms | 9.476 ms | 3.915 ms | 3.810 ms | 3.971 ms | 381.730 μs | 174.452 μs |
| materialize_kernel radial | Float64 512^3 | 92.516 ms | 142.871 ms | 76.942 ms | 45.746 ms | 75.500 ms | 34.621 ms | 33.982 ms | 35.750 ms | — | — |
| materialize_kernel radial | Float64 64^3 | 176.983 μs | 72.429 μs | 44.095 μs | 39.376 μs | 151.444 μs | 48.121 μs | 25.800 μs | 15.810 μs | 38.382 μs | 11.020 μs |
| materialize_kernel separable | Float32 128^3 | 1.797 ms | 781.498 μs | 446.815 μs | 296.831 μs | 1.534 ms | 444.255 μs | 225.752 μs | 116.621 μs | 53.450 μs | 25.750 μs |
| materialize_kernel separable | Float32 256^3 | 14.331 ms | 6.140 ms | 3.898 ms | 3.075 ms | 12.129 ms | 3.496 ms | 1.770 ms | 1.660 ms | 351.038 μs | 152.842 μs |
| materialize_kernel separable | Float32 512^3 | 114.594 ms | 49.139 ms | 31.253 ms | 24.042 ms | 97.113 ms | 28.074 ms | 34.845 ms | 18.831 ms | 5.207 ms | — |
| materialize_kernel separable | Float32 64^3 | 227.545 μs | 102.107 μs | 55.041 μs | 37.769 μs | 196.519 μs | 59.841 μs | 31.741 μs | 18.900 μs | 39.842 μs | 10.250 μs |
| materialize_kernel separable | Float64 128^3 | 1.788 ms | 972.334 μs | 772.567 μs | 535.672 μs | 1.452 ms | 454.777 μs | 241.032 μs | 287.182 μs | 74.883 μs | 36.111 μs |
| materialize_kernel separable | Float64 256^3 | 14.287 ms | 7.885 ms | 6.048 ms | 5.751 ms | 11.542 ms | 4.276 ms | 4.103 ms | 4.022 ms | 648.892 μs | 234.612 μs |
| materialize_kernel separable | Float64 512^3 | 116.085 ms | 63.147 ms | 81.939 ms | 48.531 ms | 92.240 ms | 38.007 ms | 36.530 ms | 43.457 ms | — | — |
| materialize_kernel separable | Float64 64^3 | 225.180 μs | 103.673 μs | 54.521 μs | 50.833 μs | 186.955 μs | 61.851 μs | 33.250 μs | 19.370 μs | 42.113 μs | 12.061 μs |
| radial_kernel | Float32 128^3 | 0.803 ns | 1.193 ns | 1.194 ns | 1.194 ns | 0.960 ns | 1.329 ns | 1.330 ns | 1.330 ns | 329.831 ns | 309.757 ns |
| radial_kernel | Float32 256^3 | 0.803 ns | 1.194 ns | 1.193 ns | 1.194 ns | 0.960 ns | 1.330 ns | 1.330 ns | 1.330 ns | 321.031 ns | 311.568 ns |
| radial_kernel | Float32 512^3 | 0.803 ns | 1.195 ns | 1.194 ns | 1.194 ns | 0.959 ns | 1.330 ns | 1.330 ns | 0.960 ns | 320.269 ns | — |
| radial_kernel | Float32 64^3 | 0.819 ns | 1.195 ns | 1.194 ns | 1.195 ns | 0.959 ns | 1.330 ns | 1.330 ns | 0.980 ns | 330.570 ns | 309.755 ns |
| radial_kernel | Float64 128^3 | 0.803 ns | 1.290 ns | 1.219 ns | 1.193 ns | 1.330 ns | 1.340 ns | 0.960 ns | 1.330 ns | 327.885 ns | 309.542 ns |
| radial_kernel | Float64 256^3 | 0.803 ns | 1.392 ns | 1.196 ns | 1.194 ns | 1.330 ns | 1.329 ns | 0.960 ns | 1.330 ns | 331.798 ns | 315.616 ns |
| radial_kernel | Float64 512^3 | 0.803 ns | 1.392 ns | 1.194 ns | 1.193 ns | 1.330 ns | 1.330 ns | 0.960 ns | 1.320 ns | — | — |
| radial_kernel | Float64 64^3 | 0.803 ns | 1.391 ns | 1.195 ns | 1.194 ns | 1.340 ns | 1.330 ns | 0.960 ns | 0.960 ns | 330.665 ns | 308.820 ns |
| spectral_band | Float32 128^3 | 0.803 ns | 1.194 ns | 1.219 ns | 1.195 ns | 0.960 ns | 1.329 ns | 0.960 ns | 0.970 ns | 326.191 ns | 308.408 ns |
| spectral_band | Float32 256^3 | 0.803 ns | 1.194 ns | 1.195 ns | 1.194 ns | 0.960 ns | 1.330 ns | 1.330 ns | 0.960 ns | 322.173 ns | 308.305 ns |
| spectral_band | Float32 512^3 | 0.803 ns | 1.194 ns | 1.194 ns | 1.194 ns | 0.959 ns | 1.330 ns | 1.330 ns | 0.960 ns | 319.587 ns | — |
| spectral_band | Float32 64^3 | 0.820 ns | 1.219 ns | 1.195 ns | 1.194 ns | 0.959 ns | 1.340 ns | 1.330 ns | 1.010 ns | 326.009 ns | 313.790 ns |
| spectral_band | Float64 128^3 | 0.803 ns | 1.196 ns | 1.195 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 326.665 ns | 308.775 ns |
| spectral_band | Float64 256^3 | 0.802 ns | 1.221 ns | 1.219 ns | 1.193 ns | 1.330 ns | 0.959 ns | 0.960 ns | 1.330 ns | 328.926 ns | 309.050 ns |
| spectral_band | Float64 512^3 | 0.803 ns | 1.197 ns | 1.195 ns | 1.192 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | — | — |
| spectral_band | Float64 64^3 | 0.803 ns | 1.195 ns | 1.194 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 325.250 ns | 309.266 ns |
| spectral_cutoff | Float32 128^3 | 0.803 ns | 1.194 ns | 1.193 ns | 1.193 ns | 1.330 ns | 1.340 ns | 1.330 ns | 1.330 ns | 325.436 ns | 308.239 ns |
| spectral_cutoff | Float32 256^3 | 0.803 ns | 1.196 ns | 1.217 ns | 1.193 ns | 1.330 ns | 1.330 ns | 0.960 ns | 0.990 ns | 321.170 ns | 313.970 ns |
| spectral_cutoff | Float32 512^3 | 0.803 ns | 1.219 ns | 1.193 ns | 1.218 ns | 1.329 ns | 1.330 ns | 1.330 ns | 1.330 ns | 317.395 ns | — |
| spectral_cutoff | Float32 64^3 | 0.803 ns | 1.194 ns | 1.193 ns | 1.193 ns | 1.329 ns | 1.330 ns | 1.330 ns | 0.960 ns | 323.729 ns | 310.331 ns |
| spectral_cutoff | Float64 128^3 | 0.803 ns | 1.193 ns | 1.220 ns | 1.194 ns | 1.330 ns | 0.960 ns | 0.960 ns | 0.950 ns | 328.724 ns | 310.461 ns |
| spectral_cutoff | Float64 256^3 | 0.803 ns | 1.194 ns | 1.220 ns | 1.195 ns | 1.330 ns | 1.320 ns | 0.960 ns | 1.330 ns | 325.535 ns | 314.920 ns |
| spectral_cutoff | Float64 512^3 | 0.803 ns | 1.218 ns | 1.220 ns | 1.218 ns | 1.330 ns | 1.330 ns | 0.950 ns | 1.320 ns | — | — |
| spectral_cutoff | Float64 64^3 | 0.803 ns | 1.218 ns | 1.195 ns | 1.193 ns | 1.330 ns | 1.330 ns | 0.960 ns | 1.330 ns | 326.791 ns | 308.893 ns |
| translation_kernel | Float32 128^3 | 1.795 μs | 1.804 μs | 1.851 μs | 1.819 μs | 1.409 μs | 1.415 μs | 1.414 μs | 1.420 μs | 53.639 μs | 16.200 μs |
| translation_kernel | Float32 256^3 | 3.535 μs | 3.543 μs | 3.550 μs | 3.592 μs | 2.730 μs | 2.719 μs | 2.722 μs | 2.726 μs | 53.241 μs | 16.040 μs |
| translation_kernel | Float32 512^3 | 6.890 μs | 6.908 μs | 6.904 μs | 6.933 μs | 5.263 μs | 5.258 μs | 5.282 μs | 5.267 μs | 51.266 μs | — |
| translation_kernel | Float32 64^3 | 897.860 ns | 902.929 ns | 911.951 ns | 900.658 ns | 738.091 ns | 741.325 ns | 739.068 ns | 744.111 ns | 55.253 μs | 16.060 μs |
| translation_kernel | Float64 128^3 | 2.010 μs | 2.134 μs | 2.020 μs | 2.074 μs | 1.847 μs | 1.857 μs | 1.835 μs | 1.824 μs | 61.541 μs | 17.670 μs |
| translation_kernel | Float64 256^3 | 3.830 μs | 3.821 μs | 3.834 μs | 3.947 μs | 3.481 μs | 3.487 μs | 3.466 μs | 3.505 μs | 60.245 μs | 18.461 μs |
| translation_kernel | Float64 512^3 | 7.310 μs | 7.296 μs | 7.311 μs | 7.501 μs | 6.850 μs | 6.730 μs | 6.813 μs | 6.835 μs | — | — |
| translation_kernel | Float64 64^3 | 1.011 μs | 1.018 μs | 1.083 μs | 1.032 μs | 940.750 ns | 936.154 ns | 935.172 ns | 978.214 ns | 59.045 μs | 17.090 μs |
| translation_kernel! | Float32 128^3 | 1.857 μs | 1.774 μs | 1.755 μs | 1.762 μs | 1.367 μs | 1.374 μs | 1.366 μs | 1.372 μs | 31.686 μs | 13.350 μs |
| translation_kernel! | Float32 256^3 | 3.407 μs | 3.432 μs | 3.413 μs | 3.416 μs | 2.618 μs | 2.621 μs | 2.617 μs | 2.613 μs | 35.119 μs | 13.360 μs |
| translation_kernel! | Float32 512^3 | 6.714 μs | 6.726 μs | 6.733 μs | 6.795 μs | 5.110 μs | 5.117 μs | 5.108 μs | 5.420 μs | 31.667 μs | — |
| translation_kernel! | Float32 64^3 | 856.651 ns | 864.484 ns | 857.397 ns | 856.586 ns | 704.641 ns | 705.082 ns | 702.664 ns | 700.566 ns | 35.232 μs | 13.500 μs |
| translation_kernel! | Float64 128^3 | 1.897 μs | 1.865 μs | 1.859 μs | 1.878 μs | 1.707 μs | 1.707 μs | 1.706 μs | 1.699 μs | 36.949 μs | 14.630 μs |
| translation_kernel! | Float64 256^3 | 3.585 μs | 3.617 μs | 3.603 μs | 3.624 μs | 3.321 μs | 3.255 μs | 3.276 μs | 3.298 μs | 37.060 μs | 15.620 μs |
| translation_kernel! | Float64 512^3 | 7.111 μs | 7.139 μs | 7.069 μs | 7.160 μs | 6.386 μs | 6.364 μs | 6.390 μs | 6.514 μs | — | — |
| translation_kernel! | Float64 64^3 | 961.579 ns | 967.368 ns | 961.000 ns | 966.200 ns | 885.020 ns | 890.455 ns | 886.078 ns | 886.365 ns | 38.003 μs | 14.590 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom ordered | Float32 128^3 | 22.150 ms | 11.510 ms | 5.823 ms | 3.501 ms | 20.309 ms | 10.271 ms | 5.271 ms | 2.862 ms | 154.151 μs | 130.331 μs |
| anterpolate! CatmullRom ordered | Float32 256^3 | 188.335 ms | 98.427 ms | 51.682 ms | 28.791 ms | 164.795 ms | 82.857 ms | 41.579 ms | 21.886 ms | 1.008 ms | 1.004 ms |
| anterpolate! CatmullRom ordered | Float32 512^3 | 2.076 s | 1.067 s | 554.772 ms | 303.736 ms | 1.524 s | 766.143 ms | 401.509 ms | 202.467 ms | — | — |
| anterpolate! CatmullRom ordered | Float32 64^3 | 2.760 ms | 1.497 ms | 925.148 μs | 648.694 μs | 2.437 ms | 1.292 ms | 780.495 μs | 526.385 μs | 60.873 μs | 46.890 μs |
| anterpolate! CatmullRom ordered | Float64 128^3 | 23.074 ms | 11.879 ms | 6.293 ms | 3.626 ms | 21.649 ms | 10.900 ms | 5.708 ms | 3.195 ms | 247.832 μs | 142.422 μs |
| anterpolate! CatmullRom ordered | Float64 256^3 | 231.205 ms | 120.869 ms | 63.630 ms | 36.424 ms | 172.590 ms | 88.056 ms | 45.682 ms | 24.808 ms | 1.742 ms | 1.415 ms |
| anterpolate! CatmullRom ordered | Float64 512^3 | 2.431 s | 1.276 s | 688.011 ms | 406.898 ms | 2.015 s | 1.048 s | 530.728 ms | 286.832 ms | — | — |
| anterpolate! CatmullRom ordered | Float64 64^3 | 2.793 ms | 1.541 ms | 960.305 μs | 680.487 μs | 2.451 ms | 1.303 ms | 790.662 μs | 535.844 μs | 104.660 μs | 48.531 μs |
| anterpolate! CatmullRom vector ordered | Float32 128^3 | 67.648 ms | 36.096 ms | 18.228 ms | 10.546 ms | 59.561 ms | 29.956 ms | 15.254 ms | 8.239 ms | 397.145 μs | 368.894 μs |
| anterpolate! CatmullRom vector ordered | Float32 256^3 | 590.342 ms | 323.136 ms | 157.489 ms | 89.725 ms | 478.144 ms | 240.565 ms | 123.333 ms | 64.428 ms | 2.871 ms | 3.061 ms |
| anterpolate! CatmullRom vector ordered | Float32 512^3 | 5.789 s | 3.035 s | 1.594 s | 901.803 ms | 4.508 s | 2.258 s | 1.136 s | 588.836 ms | — | — |
| anterpolate! CatmullRom vector ordered | Float32 64^3 | 8.449 ms | 4.598 ms | 2.964 ms | 2.040 ms | 7.216 ms | 3.818 ms | 2.303 ms | 1.549 ms | 122.033 μs | 122.921 μs |
| anterpolate! CatmullRom vector ordered | Float64 128^3 | 73.167 ms | 38.565 ms | 20.829 ms | 12.751 ms | 59.660 ms | 30.501 ms | 15.651 ms | 8.687 ms | 654.140 μs | 480.695 μs |
| anterpolate! CatmullRom vector ordered | Float64 256^3 | 700.837 ms | 361.425 ms | 191.173 ms | 113.031 ms | 536.203 ms | 266.221 ms | 145.972 ms | 78.469 ms | 5.038 ms | 4.401 ms |
| anterpolate! CatmullRom vector ordered | Float64 512^3 | 6.611 s | 3.480 s | 1.912 s | 1.141 s | 5.291 s | 2.752 s | 1.432 s | 748.866 ms | — | — |
| anterpolate! CatmullRom vector ordered | Float64 64^3 | 8.621 ms | 4.705 ms | 2.918 ms | 2.026 ms | 7.492 ms | 4.083 ms | 2.451 ms | 1.655 ms | 249.805 μs | 107.571 μs |
| anterpolate! CatmullRom vector | Float32 128^3 | 81.514 ms | 40.430 ms | 20.648 ms | 11.951 ms | 63.347 ms | 32.069 ms | 16.458 ms | 9.066 ms | 480.734 μs | 362.184 μs |
| anterpolate! CatmullRom vector | Float32 256^3 | 934.592 ms | 499.817 ms | 331.791 ms | 239.019 ms | 839.624 ms | 417.953 ms | 216.732 ms | 115.257 ms | 8.160 ms | 10.706 ms |
| anterpolate! CatmullRom vector | Float32 512^3 | 7.667 s | 4.064 s | 2.467 s | 1.987 s | 9.088 s | 4.699 s | 2.452 s | 1.359 s | — | — |
| anterpolate! CatmullRom vector | Float32 64^3 | 9.382 ms | 4.872 ms | 3.118 ms | 2.160 ms | 7.236 ms | 3.975 ms | 2.514 ms | 1.751 ms | 126.391 μs | 114.931 μs |
| anterpolate! CatmullRom vector | Float64 128^3 | 100.099 ms | 54.382 ms | 30.850 ms | 22.301 ms | 65.854 ms | 34.317 ms | 17.776 ms | 10.178 ms | 696.236 μs | 647.338 μs |
| anterpolate! CatmullRom vector | Float64 256^3 | 969.583 ms | 524.595 ms | 372.347 ms | 276.167 ms | 1.041 s | 525.115 ms | 280.464 ms | 158.339 ms | 12.021 ms | 14.590 ms |
| anterpolate! CatmullRom vector | Float64 512^3 | 8.873 s | 4.770 s | 2.786 s | 2.234 s | 9.067 s | 4.699 s | 2.486 s | 1.441 s | — | — |
| anterpolate! CatmullRom vector | Float64 64^3 | 9.796 ms | 4.948 ms | 3.088 ms | 2.460 ms | 7.973 ms | 4.329 ms | 2.699 ms | 1.895 ms | 224.830 μs | 110.832 μs |
| anterpolate! CatmullRom | Float32 128^3 | 25.756 ms | 12.366 ms | 6.468 ms | 4.479 ms | 20.438 ms | 10.763 ms | 5.800 ms | 3.421 ms | 184.735 μs | 126.031 μs |
| anterpolate! CatmullRom | Float32 256^3 | 287.710 ms | 154.925 ms | 84.862 ms | 57.750 ms | 168.065 ms | 88.371 ms | 44.747 ms | 24.080 ms | 1.415 ms | 2.781 ms |
| anterpolate! CatmullRom | Float32 512^3 | 2.630 s | 1.417 s | 879.999 ms | 674.157 ms | 2.949 s | 1.508 s | 764.224 ms | 439.786 ms | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 2.911 ms | 1.671 ms | 1.041 ms | 745.017 μs | 2.444 ms | 1.378 ms | 874.406 μs | 617.425 μs | 67.410 μs | 44.031 μs |
| anterpolate! CatmullRom | Float64 128^3 | 27.696 ms | 13.247 ms | 6.733 ms | 4.030 ms | 21.817 ms | 11.500 ms | 6.331 ms | 3.786 ms | 243.323 μs | 148.062 μs |
| anterpolate! CatmullRom | Float64 256^3 | 322.349 ms | 178.081 ms | 107.719 ms | 87.273 ms | 260.633 ms | 132.767 ms | 68.338 ms | 36.060 ms | 2.567 ms | 4.551 ms |
| anterpolate! CatmullRom | Float64 512^3 | 2.951 s | 1.590 s | 912.666 ms | 748.200 ms | 3.105 s | 1.561 s | 817.345 ms | 491.274 ms | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.013 ms | 1.689 ms | 1.071 ms | 783.159 μs | 2.464 ms | 1.428 ms | 936.533 μs | 674.486 μs | 93.148 μs | 50.540 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 175.110 ms | 88.522 ms | 44.675 ms | 24.868 ms | 154.348 ms | 77.724 ms | 39.325 ms | 21.099 ms | 1.153 ms | 888.519 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 1.634 s | 852.769 ms | 436.554 ms | 271.828 ms | 1.241 s | 623.769 ms | 312.312 ms | 157.502 ms | 9.810 ms | 14.921 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | 13.925 s | 7.283 s | 4.032 s | 2.910 s | 12.241 s | 6.038 s | 3.086 s | 1.796 s | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 21.184 ms | 11.596 ms | 7.110 ms | 4.890 ms | 19.197 ms | 10.369 ms | 6.338 ms | 4.284 ms | 337.157 μs | 246.633 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 180.009 ms | 90.612 ms | 45.510 ms | 25.405 ms | 154.673 ms | 78.066 ms | 39.649 ms | 21.345 ms | 1.586 ms | 941.421 μs |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 1.756 s | 928.836 ms | 507.430 ms | 379.622 ms | 1.389 s | 690.305 ms | 352.420 ms | 181.602 ms | 17.698 ms | 24.200 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | 15.200 s | 7.900 s | 4.337 s | 3.225 s | 18.663 s | 9.392 s | 4.974 s | 2.764 s | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 21.759 ms | 11.717 ms | 7.201 ms | 5.110 ms | 19.227 ms | 10.428 ms | 6.424 ms | 4.334 ms | 511.547 μs | 275.433 μs |
| anterpolate! NUFFT | Float32 128^3 | 411.356 ms | 229.080 ms | 122.227 ms | 95.784 ms | 371.481 ms | 192.571 ms | 96.379 ms | 71.032 ms | 3.013 ms | 2.717 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.229 s | 2.401 s | 1.478 s | 1.126 s | 3.720 s | 1.921 s | 1.112 s | 673.342 ms | 33.093 ms | 28.811 ms |
| anterpolate! NUFFT | Float32 512^3 | 39.107 s | 21.584 s | 12.695 s | 9.236 s | 31.263 s | 16.464 s | 9.084 s | 5.528 s | — | — |
| anterpolate! NUFFT | Float32 64^3 | 31.875 ms | 17.605 ms | 11.307 ms | 8.138 ms | 27.531 ms | 14.541 ms | 8.717 ms | 5.929 ms | 517.704 μs | 332.824 μs |
| anterpolate! NUFFT | Float64 128^3 | 535.549 ms | 308.286 ms | 214.999 ms | 178.365 ms | 422.819 ms | 236.173 ms | 132.408 ms | 102.856 ms | 9.565 ms | 6.623 ms |
| anterpolate! NUFFT | Float64 256^3 | 4.989 s | 2.865 s | 1.915 s | 1.534 s | 3.617 s | 2.031 s | 1.226 s | 870.954 ms | 71.742 ms | 58.741 ms |
| anterpolate! NUFFT | Float64 512^3 | 45.051 s | 25.253 s | 16.068 s | 12.706 s | 39.619 s | 21.765 s | 12.652 s | 8.351 s | — | — |
| anterpolate! NUFFT | Float64 64^3 | 37.138 ms | 22.056 ms | 14.408 ms | 11.002 ms | 33.385 ms | 18.044 ms | 10.656 ms | 7.180 ms | 946.997 μs | 709.767 μs |
| anterpolate! trilinear | Float32 128^3 | 3.964 ms | 1.971 ms | 1.112 ms | 744.393 μs | 4.289 ms | 2.292 ms | 1.307 ms | 723.257 μs | 52.090 μs | 24.830 μs |
| anterpolate! trilinear | Float32 256^3 | 62.706 ms | 35.555 ms | 22.635 ms | 17.192 ms | 42.314 ms | 22.641 ms | 11.589 ms | 6.464 ms | 304.980 μs | 676.165 μs |
| anterpolate! trilinear | Float32 512^3 | 550.184 ms | 317.090 ms | 221.758 ms | 176.659 ms | 552.749 ms | 286.343 ms | 149.999 ms | 87.741 ms | — | — |
| anterpolate! trilinear | Float32 64^3 | 406.626 μs | 260.555 μs | 183.888 μs | 139.043 μs | 345.279 μs | 203.682 μs | 147.130 μs | 107.861 μs | 35.478 μs | 13.050 μs |
| anterpolate! trilinear | Float64 128^3 | 4.397 ms | 2.307 ms | 1.356 ms | 947.035 μs | 6.178 ms | 3.061 ms | 1.707 ms | 1.035 ms | 63.394 μs | 38.631 μs |
| anterpolate! trilinear | Float64 256^3 | 70.000 ms | 42.217 ms | 29.841 ms | 24.553 ms | 59.429 ms | 30.800 ms | 16.824 ms | 9.353 ms | 680.954 μs | 1.053 ms |
| anterpolate! trilinear | Float64 512^3 | 596.800 ms | 352.029 ms | 232.093 ms | 201.287 ms | 566.846 ms | 292.374 ms | 167.701 ms | 99.742 ms | — | — |
| anterpolate! trilinear | Float64 64^3 | 449.476 μs | 284.373 μs | 205.973 μs | 168.676 μs | 353.659 μs | 221.533 μs | 153.240 μs | 116.161 μs | 45.292 μs | 19.790 μs |
| displace! 1-term | Float32 128^3 | 53.151 μs | 35.060 μs | 19.612 μs | 12.990 μs | 45.721 μs | 26.320 μs | 14.340 μs | 9.280 μs | 26.834 μs | 7.683 μs |
| displace! 1-term | Float32 256^3 | 427.423 μs | 262.995 μs | 133.983 μs | 72.861 μs | 366.278 μs | 185.981 μs | 96.961 μs | 51.370 μs | 40.207 μs | 18.180 μs |
| displace! 1-term | Float32 512^3 | 5.600 ms | 4.822 ms | 4.418 ms | 4.084 ms | 3.338 ms | 1.674 ms | 917.426 μs | 730.658 μs | — | — |
| displace! 1-term | Float32 64^3 | 6.604 μs | 7.141 μs | 5.367 μs | 5.623 μs | 5.735 μs | 4.873 μs | 3.571 μs | 4.073 μs | 24.534 μs | 6.308 μs |
| displace! 1-term | Float64 128^3 | 64.127 μs | 36.350 μs | 19.806 μs | 14.226 μs | 48.690 μs | 26.321 μs | 14.320 μs | 10.320 μs | 25.494 μs | 7.810 μs |
| displace! 1-term | Float64 256^3 | 764.605 μs | 557.157 μs | 337.018 μs | 214.903 μs | 397.407 μs | 202.960 μs | 98.591 μs | 53.411 μs | 45.849 μs | 19.560 μs |
| displace! 1-term | Float64 512^3 | 10.839 ms | 10.408 ms | 9.634 ms | 9.106 ms | 5.234 ms | 4.218 ms | 3.891 ms | 3.967 ms | — | — |
| displace! 1-term | Float64 64^3 | 6.901 μs | 7.084 μs | 5.443 μs | 6.605 μs | 5.904 μs | 5.263 μs | 3.579 μs | 4.071 μs | 22.251 μs | 6.410 μs |
| displace! 3-term torus | Float32 128^3 | 852.590 μs | 479.035 μs | 253.276 μs | 159.987 μs | 707.240 μs | 402.167 μs | 210.382 μs | 120.562 μs | 62.827 μs | 23.400 μs |
| displace! 3-term torus | Float32 256^3 | 6.885 ms | 3.740 ms | 1.933 ms | 1.226 ms | 5.675 ms | 3.104 ms | 1.600 ms | 813.338 μs | 64.206 μs | 31.430 μs |
| displace! 3-term torus | Float32 512^3 | 56.461 ms | 41.604 ms | 15.814 ms | 9.884 ms | 45.894 ms | 24.728 ms | 12.473 ms | 6.400 ms | — | — |
| displace! 3-term torus | Float32 64^3 | 105.769 μs | 105.837 μs | 105.729 μs | 106.055 μs | 88.089 μs | 88.461 μs | 88.060 μs | 88.140 μs | 58.142 μs | 22.820 μs |
| displace! 3-term torus | Float64 128^3 | 863.284 μs | 481.175 μs | 254.980 μs | 160.632 μs | 737.885 μs | 418.956 μs | 217.122 μs | 122.951 μs | 66.448 μs | 27.580 μs |
| displace! 3-term torus | Float64 256^3 | 6.860 ms | 3.731 ms | 1.955 ms | 1.396 ms | 5.924 ms | 3.276 ms | 1.649 ms | 858.498 μs | 103.904 μs | 109.251 μs |
| displace! 3-term torus | Float64 512^3 | 54.965 ms | 30.117 ms | 18.989 ms | 16.959 ms | 47.500 ms | 26.028 ms | 13.077 ms | 8.865 ms | — | — |
| displace! 3-term torus | Float64 64^3 | 106.364 μs | 106.443 μs | 105.912 μs | 106.311 μs | 91.752 μs | 91.781 μs | 91.940 μs | 92.101 μs | 59.861 μs | 24.411 μs |
| displace! 3-term | Float32 128^3 | 163.610 μs | 103.117 μs | 56.044 μs | 34.323 μs | 93.991 μs | 78.939 μs | 41.540 μs | 24.260 μs | 25.445 μs | 8.760 μs |
| displace! 3-term | Float32 256^3 | 1.424 ms | 838.577 μs | 444.136 μs | 239.775 μs | 758.646 μs | 602.844 μs | 308.763 μs | 160.471 μs | 45.951 μs | 22.690 μs |
| displace! 3-term | Float32 512^3 | 11.803 ms | 8.742 ms | 8.480 ms | 7.664 ms | 7.737 ms | 5.313 ms | 3.433 ms | 3.448 ms | — | — |
| displace! 3-term | Float32 64^3 | 20.474 μs | 17.564 μs | 12.311 μs | 10.846 μs | 11.569 μs | 13.040 μs | 8.353 μs | 7.310 μs | 24.837 μs | 7.143 μs |
| displace! 3-term | Float64 128^3 | 163.964 μs | 107.052 μs | 56.588 μs | 35.261 μs | 98.940 μs | 80.601 μs | 42.941 μs | 25.270 μs | 33.122 μs | 9.820 μs |
| displace! 3-term | Float64 256^3 | 1.954 ms | 1.643 ms | 1.372 ms | 1.223 ms | 794.594 μs | 623.731 μs | 320.233 μs | 170.151 μs | 64.729 μs | 69.381 μs |
| displace! 3-term | Float64 512^3 | 19.022 ms | 18.480 ms | 16.932 ms | 15.893 ms | 12.062 ms | 9.438 ms | 8.844 ms | 8.776 ms | — | — |
| displace! 3-term | Float64 64^3 | 20.483 μs | 17.917 μs | 12.085 μs | 10.436 μs | 12.090 μs | 12.990 μs | 8.474 μs | 7.230 μs | 26.669 μs | 7.427 μs |
| interpolate! CatmullRom ordered | Float32 128^3 | 3.978 ms | 2.025 ms | 1.016 ms | 563.027 μs | 2.858 ms | 1.443 ms | 728.217 μs | 384.463 μs | 62.646 μs | 28.591 μs |
| interpolate! CatmullRom ordered | Float32 256^3 | 45.036 ms | 22.584 ms | 11.896 ms | 6.500 ms | 24.792 ms | 13.066 ms | 6.401 ms | 3.512 ms | 264.681 μs | 152.731 μs |
| interpolate! CatmullRom ordered | Float32 512^3 | 771.718 ms | 394.482 ms | 208.103 ms | 122.775 ms | 539.330 ms | 290.303 ms | 155.431 ms | 79.720 ms | — | — |
| interpolate! CatmullRom ordered | Float32 64^3 | 434.192 μs | 238.193 μs | 144.776 μs | 101.942 μs | 298.069 μs | 159.162 μs | 96.780 μs | 66.251 μs | 34.788 μs | 15.081 μs |
| interpolate! CatmullRom ordered | Float64 128^3 | 4.557 ms | 2.327 ms | 1.169 ms | 626.204 μs | 3.117 ms | 1.575 ms | 793.076 μs | 420.424 μs | 107.788 μs | 79.981 μs |
| interpolate! CatmullRom ordered | Float64 256^3 | 73.457 ms | 39.162 ms | 20.571 ms | 11.320 ms | 38.737 ms | 19.138 ms | 11.345 ms | 7.578 ms | 713.146 μs | 485.645 μs |
| interpolate! CatmullRom ordered | Float64 512^3 | 963.407 ms | 503.214 ms | 296.321 ms | 190.177 ms | 817.919 ms | 448.740 ms | 240.948 ms | 142.441 ms | — | — |
| interpolate! CatmullRom ordered | Float64 64^3 | 449.682 μs | 246.581 μs | 151.595 μs | 106.420 μs | 319.868 μs | 174.243 μs | 104.990 μs | 71.001 μs | 67.195 μs | 41.821 μs |
| interpolate! CatmullRom vector ordered | Float32 128^3 | 9.700 ms | 5.144 ms | 2.571 ms | 1.390 ms | 6.185 ms | 3.086 ms | 1.556 ms | 828.278 μs | 116.373 μs | 63.721 μs |
| interpolate! CatmullRom vector ordered | Float32 256^3 | 111.773 ms | 76.771 ms | 28.811 ms | 15.811 ms | 88.630 ms | 44.261 ms | 23.053 ms | 13.604 ms | 973.127 μs | 363.243 μs |
| interpolate! CatmullRom vector ordered | Float32 512^3 | 1.940 s | 1.090 s | 698.464 ms | 472.691 ms | 1.192 s | 634.506 ms | 340.281 ms | 182.591 ms | — | — |
| interpolate! CatmullRom vector ordered | Float32 64^3 | 1.017 ms | 554.127 μs | 332.848 μs | 238.215 μs | 679.499 μs | 362.385 μs | 221.591 μs | 150.281 μs | 59.070 μs | 27.410 μs |
| interpolate! CatmullRom vector ordered | Float64 128^3 | 12.268 ms | 6.518 ms | 3.541 ms | 2.389 ms | 6.719 ms | 3.444 ms | 1.723 ms | 948.968 μs | 240.450 μs | 172.792 μs |
| interpolate! CatmullRom vector ordered | Float64 256^3 | 188.781 ms | 94.515 ms | 50.188 ms | 34.708 ms | 170.481 ms | 85.581 ms | 50.086 ms | 28.996 ms | 1.844 ms | 1.180 ms |
| interpolate! CatmullRom vector ordered | Float64 512^3 | 2.292 s | 1.244 s | 748.016 ms | 517.239 ms | 1.697 s | 934.697 ms | 506.707 ms | 269.835 ms | — | — |
| interpolate! CatmullRom vector ordered | Float64 64^3 | 1.089 ms | 595.344 μs | 364.686 μs | 250.088 μs | 775.471 μs | 418.005 μs | 254.131 μs | 168.871 μs | 114.922 μs | 86.111 μs |
| interpolate! CatmullRom vector | Float32 128^3 | 22.551 ms | 12.099 ms | 6.750 ms | 3.667 ms | 7.680 ms | 3.908 ms | 1.965 ms | 1.075 ms | 277.350 μs | 204.882 μs |
| interpolate! CatmullRom vector | Float32 256^3 | 407.357 ms | 241.772 ms | 169.663 ms | 97.564 ms | 295.710 ms | 145.017 ms | 77.091 ms | 42.675 ms | 3.909 ms | 3.282 ms |
| interpolate! CatmullRom vector | Float32 512^3 | 3.208 s | 2.025 s | 1.423 s | 867.578 ms | 2.924 s | 1.506 s | 796.297 ms | 474.708 ms | — | — |
| interpolate! CatmullRom vector | Float32 64^3 | 1.182 ms | 628.861 μs | 389.213 μs | 277.421 μs | 818.528 μs | 444.196 μs | 265.662 μs | 181.051 μs | 68.320 μs | 75.311 μs |
| interpolate! CatmullRom vector | Float64 128^3 | 39.020 ms | 23.656 ms | 14.998 ms | 9.582 ms | 8.973 ms | 4.878 ms | 2.481 ms | 1.658 ms | 349.816 μs | 244.233 μs |
| interpolate! CatmullRom vector | Float64 256^3 | 417.022 ms | 253.550 ms | 166.543 ms | 104.000 ms | 364.836 ms | 182.829 ms | 102.296 ms | 58.646 ms | 6.321 ms | 4.786 ms |
| interpolate! CatmullRom vector | Float64 512^3 | 3.734 s | 2.115 s | 1.419 s | 914.247 ms | 3.369 s | 1.746 s | 932.732 ms | 567.233 ms | — | — |
| interpolate! CatmullRom vector | Float64 64^3 | 1.245 ms | 653.658 μs | 403.137 μs | 282.359 μs | 873.993 μs | 468.306 μs | 283.631 μs | 191.041 μs | 127.768 μs | 90.011 μs |
| interpolate! CatmullRom | Float32 128^3 | 4.286 ms | 2.207 ms | 1.156 ms | 626.590 μs | 3.175 ms | 1.609 ms | 813.568 μs | 437.365 μs | 109.047 μs | 74.921 μs |
| interpolate! CatmullRom | Float32 256^3 | 122.386 ms | 75.380 ms | 45.126 ms | 27.806 ms | 31.599 ms | 19.518 ms | 8.375 ms | 4.974 ms | 815.020 μs | 767.616 μs |
| interpolate! CatmullRom | Float32 512^3 | 1.175 s | 705.954 ms | 475.355 ms | 295.824 ms | 1.164 s | 598.429 ms | 316.114 ms | 192.771 ms | — | — |
| interpolate! CatmullRom | Float32 64^3 | 460.844 μs | 252.906 μs | 154.673 μs | 108.709 μs | 328.489 μs | 174.362 μs | 105.010 μs | 73.570 μs | 44.438 μs | 29.641 μs |
| interpolate! CatmullRom | Float64 128^3 | 6.201 ms | 3.041 ms | 1.490 ms | 839.866 μs | 3.421 ms | 1.738 ms | 905.547 μs | 523.745 μs | 122.843 μs | 103.621 μs |
| interpolate! CatmullRom | Float64 256^3 | 143.689 ms | 91.436 ms | 53.551 ms | 36.410 ms | 103.391 ms | 53.986 ms | 27.520 ms | 14.665 ms | 1.545 ms | 1.491 ms |
| interpolate! CatmullRom | Float64 512^3 | 1.274 s | 746.829 ms | 495.176 ms | 330.954 ms | 1.463 s | 708.467 ms | 386.254 ms | 263.106 ms | — | — |
| interpolate! CatmullRom | Float64 64^3 | 498.063 μs | 271.026 μs | 167.332 μs | 117.412 μs | 380.600 μs | 206.292 μs | 125.070 μs | 86.011 μs | 64.124 μs | 43.191 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 22.677 ms | 11.577 ms | 5.894 ms | 3.783 ms | 17.078 ms | 8.589 ms | 4.447 ms | 2.683 ms | 324.459 μs | 229.572 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 595.093 ms | 376.466 ms | 226.156 ms | 145.525 ms | 146.667 ms | 103.268 ms | 38.904 ms | 29.008 ms | 2.408 ms | 3.503 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | 5.787 s | 3.537 s | 2.479 s | 1.570 s | 4.545 s | 2.389 s | 1.395 s | 1.006 s | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 2.497 ms | 1.358 ms | 815.938 μs | 566.002 μs | 2.033 ms | 1.075 ms | 640.134 μs | 435.534 μs | 81.689 μs | 75.250 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 32.586 ms | 15.854 ms | 7.936 ms | 4.587 ms | 17.344 ms | 8.781 ms | 4.737 ms | 3.182 ms | 396.096 μs | 430.285 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 756.298 ms | 487.396 ms | 296.947 ms | 201.500 ms | 415.711 ms | 213.443 ms | 116.222 ms | 67.094 ms | 4.802 ms | 8.541 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | 6.381 s | 3.855 s | 2.681 s | 1.728 s | 5.891 s | 2.786 s | 1.454 s | 913.871 ms | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 2.797 ms | 1.508 ms | 918.995 μs | 640.034 μs | 2.099 ms | 1.104 ms | 673.722 μs | 457.644 μs | 213.473 μs | 140.002 μs |
| interpolate! NUFFT | Float32 128^3 | 325.747 ms | 186.369 ms | 123.152 ms | 104.662 ms | 255.039 ms | 133.458 ms | 75.291 ms | 59.441 ms | 1.986 ms | 1.972 ms |
| interpolate! NUFFT | Float32 256^3 | 3.500 s | 2.069 s | 1.370 s | 917.332 ms | 2.920 s | 1.548 s | 941.636 ms | 606.728 ms | 25.730 ms | 17.667 ms |
| interpolate! NUFFT | Float32 512^3 | 32.032 s | 17.990 s | 11.415 s | 8.316 s | 24.745 s | 13.332 s | 7.690 s | 4.969 s | — | — |
| interpolate! NUFFT | Float32 64^3 | 16.705 ms | 10.169 ms | 6.797 ms | 5.219 ms | 12.560 ms | 6.637 ms | 3.868 ms | 2.481 ms | 427.513 μs | 298.213 μs |
| interpolate! NUFFT | Float64 128^3 | 416.973 ms | 248.266 ms | 195.739 ms | 162.003 ms | 222.467 ms | 136.431 ms | 82.991 ms | 75.590 ms | 8.654 ms | 5.538 ms |
| interpolate! NUFFT | Float64 256^3 | 3.900 s | 2.348 s | 1.695 s | 1.394 s | 1.987 s | 1.209 s | 851.553 ms | 706.819 ms | 59.088 ms | 47.555 ms |
| interpolate! NUFFT | Float64 512^3 | 35.191 s | 20.830 s | 14.825 s | 13.183 s | 25.064 s | 14.174 s | 8.789 s | 9.453 s | — | — |
| interpolate! NUFFT | Float64 64^3 | 22.099 ms | 14.244 ms | 10.719 ms | 8.957 ms | 18.006 ms | 9.840 ms | 6.118 ms | 4.193 ms | 828.686 μs | 772.818 μs |
| interpolate! trilinear | Float32 128^3 | 1.342 ms | 694.969 μs | 353.430 μs | 197.181 μs | 1.090 ms | 557.325 μs | 278.492 μs | 150.682 μs | 31.805 μs | 15.730 μs |
| interpolate! trilinear | Float32 256^3 | 38.320 ms | 20.467 ms | 12.097 ms | 7.543 ms | 10.442 ms | 6.255 ms | 2.713 ms | 1.545 ms | 117.725 μs | 171.141 μs |
| interpolate! trilinear | Float32 512^3 | 335.141 ms | 185.452 ms | 110.428 ms | 76.718 ms | 423.538 ms | 214.260 ms | 106.460 ms | 57.539 ms | — | — |
| interpolate! trilinear | Float32 64^3 | 167.608 μs | 93.351 μs | 58.430 μs | 42.009 μs | 121.260 μs | 64.301 μs | 38.840 μs | 27.141 μs | 29.064 μs | 10.070 μs |
| interpolate! trilinear | Float64 128^3 | 1.952 ms | 875.651 μs | 447.531 μs | 264.354 μs | 1.078 ms | 545.128 μs | 280.863 μs | 151.761 μs | 46.186 μs | 26.541 μs |
| interpolate! trilinear | Float64 256^3 | 43.459 ms | 25.376 ms | 15.518 ms | 10.096 ms | 30.922 ms | 15.612 ms | 7.710 ms | 3.974 ms | 241.819 μs | 297.083 μs |
| interpolate! trilinear | Float64 512^3 | 372.865 ms | 218.219 ms | 135.777 ms | 87.993 ms | 421.500 ms | 209.163 ms | 107.257 ms | 60.957 ms | — | — |
| interpolate! trilinear | Float64 64^3 | 167.681 μs | 91.490 μs | 58.950 μs | 42.757 μs | 128.583 μs | 69.781 μs | 40.490 μs | 27.030 μs | 37.755 μs | 16.140 μs |
| point_traversal_order | Float32 128^3 | 1.020 ms | 1.193 ms | 864.955 μs | 592.713 μs | 696.250 μs | 447.016 μs | 312.933 μs | 236.243 μs | 310.671 μs | 91.601 μs |
| point_traversal_order | Float32 256^3 | 12.495 ms | 8.452 ms | 5.744 ms | 3.741 ms | 5.854 ms | 2.945 ms | 1.652 ms | 1.049 ms | 309.371 μs | 164.302 μs |
| point_traversal_order | Float32 512^3 | 136.475 ms | 74.450 ms | 42.791 ms | 26.434 ms | 56.905 ms | 30.203 ms | 16.820 ms | 10.301 ms | — | — |
| point_traversal_order | Float32 64^3 | 109.698 μs | 153.161 μs | 164.080 μs | 148.075 μs | 88.249 μs | 97.221 μs | 96.891 μs | 91.541 μs | 299.185 μs | 83.741 μs |
| point_traversal_order | Float64 128^3 | 1.025 ms | 1.097 ms | 856.873 μs | 664.379 μs | 702.816 μs | 450.847 μs | 316.323 μs | 232.413 μs | 265.348 μs | 89.571 μs |
| point_traversal_order | Float64 256^3 | 12.557 ms | 8.727 ms | 5.832 ms | 3.738 ms | 6.381 ms | 3.326 ms | 1.863 ms | 1.121 ms | 388.804 μs | 186.352 μs |
| point_traversal_order | Float64 512^3 | 138.042 ms | 77.288 ms | 43.803 ms | 27.682 ms | 60.449 ms | 32.943 ms | 18.006 ms | 11.575 ms | — | — |
| point_traversal_order | Float64 64^3 | 109.535 μs | 135.740 μs | 167.776 μs | 145.094 μs | 88.292 μs | 95.211 μs | 95.811 μs | 97.401 μs | 243.054 μs | 81.031 μs |
| point_traversal_order! | Float32 128^3 | 1.006 ms | 1.279 ms | 868.902 μs | 580.423 μs | 695.710 μs | 444.466 μs | 315.543 μs | 237.432 μs | 244.784 μs | 86.961 μs |
| point_traversal_order! | Float32 256^3 | 12.134 ms | 8.324 ms | 5.523 ms | 3.485 ms | 5.649 ms | 2.907 ms | 1.607 ms | 975.569 μs | 326.273 μs | 157.321 μs |
| point_traversal_order! | Float32 512^3 | 136.332 ms | 76.806 ms | 42.201 ms | 26.348 ms | 50.217 ms | 25.681 ms | 13.493 ms | 7.711 ms | — | — |
| point_traversal_order! | Float32 64^3 | 107.345 μs | 170.873 μs | 169.672 μs | 143.930 μs | 87.620 μs | 93.402 μs | 107.500 μs | 80.670 μs | 236.699 μs | 77.301 μs |
| point_traversal_order! | Float64 128^3 | 1.004 ms | 1.195 ms | 852.217 μs | 579.803 μs | 701.775 μs | 448.537 μs | 316.933 μs | 231.552 μs | 263.227 μs | 85.071 μs |
| point_traversal_order! | Float64 256^3 | 12.160 ms | 8.361 ms | 5.475 ms | 3.511 ms | 5.727 ms | 2.904 ms | 1.618 ms | 982.680 μs | 330.104 μs | 177.732 μs |
| point_traversal_order! | Float64 512^3 | 144.037 ms | 75.128 ms | 45.112 ms | 28.136 ms | 56.149 ms | 29.128 ms | 15.193 ms | 9.013 ms | — | — |
| point_traversal_order! | Float64 64^3 | 108.167 μs | 169.954 μs | 167.062 μs | 141.172 μs | 87.702 μs | 95.471 μs | 106.230 μs | 84.530 μs | 218.671 μs | 76.591 μs |
| wrap! | Float32 128^3 | 517.262 μs | 343.736 μs | 180.513 μs | 117.373 μs | 442.206 μs | 274.338 μs | 139.481 μs | 82.620 μs | 33.641 μs | 10.940 μs |
| wrap! | Float32 256^3 | 4.186 ms | 2.712 ms | 1.395 ms | 925.388 μs | 3.545 ms | 2.144 ms | 1.080 ms | 564.586 μs | 43.678 μs | 14.420 μs |
| wrap! | Float32 512^3 | 33.235 ms | 21.476 ms | 12.460 ms | 7.458 ms | 28.362 ms | 17.100 ms | 8.582 ms | 4.360 ms | — | — |
| wrap! | Float32 64^3 | 64.287 μs | 64.316 μs | 64.268 μs | 66.455 μs | 55.309 μs | 55.361 μs | 55.270 μs | 55.291 μs | 34.079 μs | 10.821 μs |
| wrap! | Float64 128^3 | 576.701 μs | 367.896 μs | 192.917 μs | 125.535 μs | 442.193 μs | 280.324 μs | 142.471 μs | 84.230 μs | 36.614 μs | 15.990 μs |
| wrap! | Float64 256^3 | 4.569 ms | 2.938 ms | 1.518 ms | 946.812 μs | 3.534 ms | 2.202 ms | 1.106 ms | 569.445 μs | 51.335 μs | 58.850 μs |
| wrap! | Float64 512^3 | 36.531 ms | 23.147 ms | 12.903 ms | 8.328 ms | 30.383 ms | 17.488 ms | 8.815 ms | 4.530 ms | — | — |
| wrap! | Float64 64^3 | 70.283 μs | 70.297 μs | 70.230 μs | 70.289 μs | 55.161 μs | 55.141 μs | 55.160 μs | 55.170 μs | 35.045 μs | 12.430 μs |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.085 ms | 7.072 ms | 8.665 ms | 7.738 ms | 6.955 ms | 4.966 ms | 5.817 ms | 6.135 ms | 326.361 μs | 175.881 μs |
| co-spectrum vec.vec | Float32 256^3 | 64.184 ms | 48.351 ms | 47.165 ms | 44.238 ms | 55.604 ms | 37.200 ms | 31.873 ms | 29.922 ms | 945.593 μs | 832.307 μs |
| co-spectrum vec.vec | Float32 512^3 | 518.943 ms | 375.467 ms | 267.661 ms | 234.091 ms | 440.259 ms | 268.864 ms | 187.381 ms | 161.432 ms | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.044 ms | 1.390 ms | 1.591 ms | 1.633 ms | 903.870 μs | 938.813 μs | 1.221 ms | 1.400 ms | 222.869 μs | 71.201 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.403 ms | 6.767 ms | 6.208 ms | 5.998 ms | 7.252 ms | 5.145 ms | 4.528 ms | 4.743 ms | 17.141 ms | 254.452 μs |
| co-spectrum vec.vec | Float64 256^3 | 67.206 ms | 49.072 ms | 37.143 ms | 32.504 ms | 58.802 ms | 36.914 ms | 27.157 ms | 22.471 ms | 56.217 ms | 1.156 ms |
| co-spectrum vec.vec | Float64 512^3 | 562.298 ms | 366.443 ms | 239.354 ms | 193.400 ms | 475.221 ms | 268.276 ms | 183.587 ms | 130.534 ms | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.064 ms | 898.933 μs | 1.070 ms | 985.536 μs | 936.635 μs | 738.759 μs | 853.153 μs | 948.688 μs | 6.988 ms | 77.451 μs |
| cov vector | Float32 128^3 | 2.264 ms | 1.215 ms | 631.475 μs | 339.757 μs | 1.134 ms | 578.077 μs | 297.573 μs | 177.522 μs | 589.833 μs | 146.991 μs |
| cov vector | Float32 256^3 | 20.935 ms | 13.623 ms | 11.094 ms | 10.131 ms | 12.542 ms | 6.798 ms | 4.780 ms | 4.702 ms | 2.727 ms | 827.017 μs |
| cov vector | Float32 512^3 | 171.923 ms | 115.540 ms | 94.703 ms | 89.251 ms | 96.865 ms | 64.912 ms | 55.668 ms | 55.619 ms | — | — |
| cov vector | Float32 64^3 | 252.520 μs | 140.130 μs | 77.735 μs | 63.666 μs | 140.630 μs | 79.431 μs | 45.501 μs | 34.430 μs | 328.488 μs | 84.621 μs |
| cov vector | Float64 128^3 | 4.002 ms | 2.736 ms | 2.116 ms | 1.727 ms | 2.219 ms | 1.126 ms | 574.614 μs | 328.444 μs | 838.856 μs | 188.752 μs |
| cov vector | Float64 256^3 | 34.433 ms | 26.428 ms | 23.077 ms | 21.412 ms | 22.977 ms | 15.317 ms | 12.430 ms | 12.522 ms | 4.671 ms | 1.099 ms |
| cov vector | Float64 512^3 | 277.888 ms | 214.724 ms | 189.691 ms | 179.381 ms | 182.478 ms | 128.532 ms | 109.807 ms | 111.255 ms | — | — |
| cov vector | Float64 64^3 | 350.559 μs | 191.108 μs | 105.325 μs | 72.901 μs | 273.507 μs | 146.432 μs | 81.120 μs | 53.450 μs | 368.135 μs | 97.271 μs |
| cross-correlation vec.vec | Float32 128^3 | 37.609 ms | 31.104 ms | 33.338 ms | 33.200 ms | 33.178 ms | 24.781 ms | 22.088 ms | 21.576 ms | 762.275 μs | 560.736 μs |
| cross-correlation vec.vec | Float32 256^3 | 415.659 ms | 272.092 ms | 231.945 ms | 222.598 ms | 321.542 ms | 246.208 ms | 180.937 ms | 162.080 ms | 9.860 ms | 6.504 ms |
| cross-correlation vec.vec | Float32 512^3 | 3.530 s | 2.311 s | 1.877 s | 1.663 s | 2.967 s | 1.883 s | 1.357 s | 1.137 s | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.607 ms | 5.071 ms | 5.530 ms | 5.639 ms | 3.834 ms | 3.592 ms | 3.730 ms | 3.719 ms | 237.185 μs | 156.421 μs |
| cross-correlation vec.vec | Float64 128^3 | 45.587 ms | 50.223 ms | 39.303 ms | 36.501 ms | 41.785 ms | 29.233 ms | 25.637 ms | 30.323 ms | 37.056 ms | 1.933 ms |
| cross-correlation vec.vec | Float64 256^3 | 577.413 ms | 432.232 ms | 364.778 ms | 341.609 ms | 490.672 ms | 373.548 ms | 267.280 ms | 239.944 ms | 133.731 ms | 15.054 ms |
| cross-correlation vec.vec | Float64 512^3 | 5.581 s | 3.716 s | 2.872 s | 2.569 s | 4.503 s | 2.909 s | 2.050 s | 1.757 s | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.514 ms | 5.178 ms | 5.538 ms | 5.414 ms | 4.250 ms | 3.201 ms | 3.349 ms | 3.360 ms | 12.704 ms | 256.543 μs |
| inner spectral | Float32 128^3 | 2.504 ms | 1.786 ms | 1.389 ms | 1.201 ms | 1.431 ms | 855.665 μs | 494.625 μs | 375.174 μs | 206.150 μs | 122.092 μs |
| inner spectral | Float32 256^3 | 21.795 ms | 16.376 ms | 14.809 ms | 13.845 ms | 13.019 ms | 7.760 ms | 7.044 ms | 7.068 ms | 712.198 μs | 624.066 μs |
| inner spectral | Float32 512^3 | 165.226 ms | 129.349 ms | 112.310 ms | 105.994 ms | 101.936 ms | 78.378 ms | 69.998 ms | 69.928 ms | — | — |
| inner spectral | Float32 64^3 | 304.653 μs | 196.801 μs | 141.444 μs | 115.136 μs | 203.210 μs | 122.862 μs | 87.000 μs | 77.301 μs | 197.799 μs | 71.451 μs |
| inner spectral | Float64 128^3 | 4.361 ms | 3.484 ms | 3.012 ms | 2.936 ms | 1.815 ms | 1.092 ms | 731.836 μs | 593.325 μs | 253.212 μs | 204.073 μs |
| inner spectral | Float64 256^3 | 35.040 ms | 29.944 ms | 27.508 ms | 26.356 ms | 19.156 ms | 15.936 ms | 15.622 ms | 15.032 ms | 1.178 ms | 1.114 ms |
| inner spectral | Float64 512^3 | 269.877 ms | 226.513 ms | 211.059 ms | 199.729 ms | 129.232 ms | 128.364 ms | 128.038 ms | 126.763 ms | — | — |
| inner spectral | Float64 64^3 | 318.278 μs | 207.007 μs | 150.665 μs | 129.363 μs | 229.486 μs | 128.362 μs | 91.271 μs | 86.111 μs | 201.633 μs | 81.140 μs |
| inner vec.vec | Float32 128^3 | 1.183 ms | 986.312 μs | 808.568 μs | 711.094 μs | 368.995 μs | 192.159 μs | 100.831 μs | 71.340 μs | 49.570 μs | 29.520 μs |
| inner vec.vec | Float32 256^3 | 13.199 ms | 12.158 ms | 11.339 ms | 10.763 ms | 6.902 ms | 5.986 ms | 5.913 ms | 5.910 ms | 487.189 μs | 487.904 μs |
| inner vec.vec | Float32 512^3 | 106.913 ms | 100.014 ms | 95.675 ms | 89.716 ms | 61.782 ms | 57.087 ms | 56.047 ms | 55.983 ms | — | — |
| inner vec.vec | Float32 64^3 | 69.367 μs | 38.626 μs | 20.133 μs | 13.577 μs | 45.680 μs | 25.881 μs | 14.630 μs | 10.070 μs | 51.068 μs | 12.770 μs |
| inner vec.vec | Float64 128^3 | 2.944 ms | 2.567 ms | 2.283 ms | 2.141 ms | 1.074 ms | 550.868 μs | 318.353 μs | 252.623 μs | 90.936 μs | 134.921 μs |
| inner vec.vec | Float64 256^3 | 26.374 ms | 24.722 ms | 23.378 ms | 21.747 ms | 15.415 ms | 13.524 ms | 13.355 ms | 13.310 ms | 932.844 μs | 963.340 μs |
| inner vec.vec | Float64 512^3 | 206.188 ms | 197.179 ms | 188.901 ms | 177.967 ms | 116.861 ms | 115.686 ms | 110.327 ms | 112.022 ms | — | — |
| inner vec.vec | Float64 64^3 | 140.557 μs | 75.560 μs | 39.574 μs | 25.774 μs | 87.923 μs | 46.321 μs | 25.511 μs | 17.881 μs | 45.467 μs | 18.440 μs |
| integral scalar | Float32 128^3 | 109.414 μs | 62.463 μs | 30.521 μs | 20.090 μs | 61.001 μs | 34.179 μs | 20.270 μs | 12.301 μs | 133.850 μs | 31.350 μs |
| integral scalar | Float32 256^3 | 2.389 ms | 1.617 ms | 1.279 ms | 1.187 ms | 534.961 μs | 252.132 μs | 152.442 μs | 97.441 μs | 599.569 μs | 175.142 μs |
| integral scalar | Float32 512^3 | 20.554 ms | 16.135 ms | 14.842 ms | 14.378 ms | 10.333 ms | 9.646 ms | 8.868 ms | 9.107 ms | — | — |
| integral scalar | Float32 64^3 | 10.298 μs | 7.002 μs | 5.361 μs | 5.864 μs | 6.862 μs | 4.557 μs | 4.024 μs | 5.248 μs | 79.017 μs | 17.710 μs |
| integral scalar | Float64 128^3 | 226.462 μs | 125.840 μs | 67.042 μs | 36.952 μs | 120.591 μs | 63.591 μs | 34.110 μs | 22.870 μs | 147.500 μs | 32.470 μs |
| integral scalar | Float64 256^3 | 4.349 ms | 3.617 ms | 3.263 ms | 3.035 ms | 1.917 ms | 1.128 ms | 866.159 μs | 941.949 μs | 736.276 μs | 191.192 μs |
| integral scalar | Float64 512^3 | 37.554 ms | 32.217 ms | 30.200 ms | 28.704 ms | 21.228 ms | 18.625 ms | 18.134 ms | 18.098 ms | — | — |
| integral scalar | Float64 64^3 | 25.921 μs | 13.094 μs | 8.029 μs | 7.944 μs | 15.080 μs | 8.220 μs | 5.796 μs | 5.713 μs | 79.599 μs | 19.130 μs |
| integral spectral vec | Float32 128^3 | 66.189 ns | 67.435 ns | 67.186 ns | 67.414 ns | 69.103 ns | 68.758 ns | 69.304 ns | 69.776 ns | 85.049 μs | 12.650 μs |
| integral spectral vec | Float32 256^3 | 66.410 ns | 67.491 ns | 71.998 ns | 67.375 ns | 69.362 ns | 69.396 ns | 69.755 ns | 69.858 ns | 75.956 μs | 12.770 μs |
| integral spectral vec | Float32 512^3 | 66.622 ns | 68.094 ns | 67.989 ns | 68.387 ns | 70.104 ns | 71.046 ns | 71.936 ns | 68.915 ns | — | — |
| integral spectral vec | Float32 64^3 | 66.576 ns | 67.220 ns | 67.090 ns | 67.242 ns | 70.537 ns | 68.174 ns | 70.905 ns | 69.714 ns | 80.990 μs | 12.930 μs |
| integral spectral vec | Float64 128^3 | 67.820 ns | 67.842 ns | 69.251 ns | 69.597 ns | 74.170 ns | 75.608 ns | 75.341 ns | 73.864 ns | 81.003 μs | 12.930 μs |
| integral spectral vec | Float64 256^3 | 68.036 ns | 69.177 ns | 70.275 ns | 69.669 ns | 75.482 ns | 78.498 ns | 76.359 ns | 75.166 ns | 81.676 μs | 13.400 μs |
| integral spectral vec | Float64 512^3 | 68.668 ns | 68.451 ns | 70.606 ns | 70.166 ns | 75.654 ns | 80.598 ns | 81.545 ns | 76.732 ns | — | — |
| integral spectral vec | Float64 64^3 | 67.957 ns | 68.219 ns | 69.090 ns | 68.496 ns | 76.476 ns | 78.947 ns | 77.038 ns | 77.848 ns | 83.543 μs | 13.160 μs |
| l2norm vec | Float32 128^3 | 595.688 μs | 349.452 μs | 187.633 μs | 90.543 μs | 235.134 μs | 121.969 μs | 65.510 μs | 40.210 μs | 47.923 μs | 19.940 μs |
| l2norm vec | Float32 256^3 | 7.519 ms | 5.911 ms | 5.434 ms | 5.034 ms | 3.989 ms | 2.416 ms | 1.983 ms | 2.032 ms | 261.833 μs | 258.063 μs |
| l2norm vec | Float32 512^3 | 61.152 ms | 49.387 ms | 46.089 ms | 44.710 ms | 40.077 ms | 30.323 ms | 27.346 ms | 27.074 ms | — | — |
| l2norm vec | Float32 64^3 | 49.590 μs | 27.440 μs | 15.342 μs | 12.585 μs | 29.440 μs | 17.131 μs | 9.380 μs | 7.120 μs | 48.826 μs | 12.010 μs |
| l2norm vec | Float64 128^3 | 1.575 ms | 1.089 ms | 809.456 μs | 708.307 μs | 497.825 μs | 237.744 μs | 127.191 μs | 79.041 μs | 86.910 μs | 33.941 μs |
| l2norm vec | Float64 256^3 | 14.836 ms | 12.142 ms | 10.977 ms | 10.406 ms | 10.184 ms | 6.964 ms | 5.574 ms | 5.585 ms | 540.049 μs | 491.626 μs |
| l2norm vec | Float64 512^3 | 120.453 ms | 99.144 ms | 91.153 ms | 87.669 ms | 85.303 ms | 64.429 ms | 54.552 ms | 54.748 ms | — | — |
| l2norm vec | Float64 64^3 | 92.026 μs | 50.507 μs | 27.157 μs | 20.346 μs | 56.801 μs | 29.700 μs | 16.880 μs | 10.570 μs | 43.587 μs | 17.000 μs |
| lpnorm vec Inf | Float32 128^3 | 1.381 ms | 1.242 ms | 1.106 ms | 956.961 μs | 508.627 μs | 390.458 μs | 347.964 μs | 318.423 μs | 186.119 μs | 66.061 μs |
| lpnorm vec Inf | Float32 256^3 | 13.432 ms | 13.110 ms | 11.263 ms | 11.016 ms | 7.596 ms | 8.293 ms | 7.542 ms | 8.089 ms | 1.072 ms | 505.245 μs |
| lpnorm vec Inf | Float32 512^3 | 110.235 ms | 108.705 ms | 92.782 ms | 85.620 ms | 79.075 ms | 73.696 ms | 72.190 ms | 74.125 ms | — | — |
| lpnorm vec Inf | Float32 64^3 | 96.755 μs | 85.910 μs | 69.360 μs | 77.471 μs | 61.050 μs | 49.101 μs | 41.940 μs | 42.440 μs | 91.144 μs | 24.441 μs |
| lpnorm vec Inf | Float64 128^3 | 3.069 ms | 3.051 ms | 2.658 ms | 2.458 ms | 1.204 ms | 1.089 ms | 1.031 ms | 944.049 μs | 289.463 μs | 115.202 μs |
| lpnorm vec Inf | Float64 256^3 | 27.867 ms | 26.535 ms | 23.321 ms | 21.593 ms | 16.363 ms | 16.081 ms | 15.864 ms | 15.767 ms | 1.913 ms | 956.310 μs |
| lpnorm vec Inf | Float64 512^3 | 216.590 ms | 214.431 ms | 189.028 ms | 173.911 ms | 130.561 ms | 136.760 ms | 126.840 ms | 138.605 ms | — | — |
| lpnorm vec Inf | Float64 64^3 | 235.039 μs | 180.882 μs | 146.661 μs | 156.021 μs | 110.773 μs | 92.231 μs | 76.100 μs | 73.051 μs | 106.665 μs | 34.780 μs |
| maximum scalar | Float32 128^3 | 337.764 μs | 176.549 μs | 90.750 μs | 50.518 μs | 236.653 μs | 115.830 μs | 60.900 μs | 32.610 μs | 134.032 μs | 32.391 μs |
| maximum scalar | Float32 256^3 | 3.932 ms | 2.016 ms | 1.401 ms | 1.212 ms | 1.909 ms | 917.366 μs | 477.115 μs | 244.682 μs | 606.662 μs | 174.921 μs |
| maximum scalar | Float32 512^3 | 25.096 ms | 17.126 ms | 15.422 ms | 14.664 ms | 30.283 ms | 16.112 ms | 9.583 ms | 8.179 ms | — | — |
| maximum scalar | Float32 64^3 | 42.197 μs | 24.567 μs | 14.047 μs | 10.389 μs | 29.380 μs | 16.080 μs | 9.310 μs | 6.650 μs | 74.590 μs | 17.800 μs |
| maximum scalar | Float64 128^3 | 528.797 μs | 283.995 μs | 145.437 μs | 77.542 μs | 445.675 μs | 224.803 μs | 113.841 μs | 59.271 μs | 180.314 μs | 40.610 μs |
| maximum scalar | Float64 256^3 | 6.070 ms | 3.961 ms | 3.434 ms | 3.067 ms | 4.116 ms | 2.007 ms | 1.103 ms | 784.668 μs | 966.657 μs | 214.062 μs |
| maximum scalar | Float64 512^3 | 48.697 ms | 34.187 ms | 30.824 ms | 28.774 ms | 45.125 ms | 26.574 ms | 18.993 ms | 17.451 ms | — | — |
| maximum scalar | Float64 64^3 | 65.461 μs | 36.439 μs | 20.243 μs | 18.262 μs | 55.431 μs | 29.560 μs | 15.970 μs | 10.020 μs | 83.618 μs | 24.030 μs |
| maximum(norm) vec | Float32 128^3 | 1.811 ms | 922.566 μs | 474.844 μs | 244.528 μs | 769.452 μs | 390.158 μs | 197.432 μs | 104.321 μs | 198.149 μs | 42.660 μs |
| maximum(norm) vec | Float32 256^3 | 15.033 ms | 8.192 ms | 5.677 ms | 5.050 ms | 8.066 ms | 3.807 ms | 2.333 ms | 2.105 ms | 836.865 μs | 283.613 μs |
| maximum(norm) vec | Float32 512^3 | 120.900 ms | 68.398 ms | 49.870 ms | 45.394 ms | 63.078 ms | 38.676 ms | 29.713 ms | 27.969 ms | — | — |
| maximum(norm) vec | Float32 64^3 | 222.431 μs | 116.133 μs | 61.167 μs | 35.122 μs | 95.920 μs | 50.370 μs | 26.310 μs | 15.540 μs | 93.677 μs | 20.410 μs |
| maximum(norm) vec | Float64 128^3 | 5.212 ms | 2.679 ms | 1.387 ms | 827.978 μs | 1.584 ms | 799.402 μs | 401.013 μs | 207.762 μs | 252.671 μs | 128.792 μs |
| maximum(norm) vec | Float64 256^3 | 42.269 ms | 21.413 ms | 12.905 ms | 11.074 ms | 14.203 ms | 7.962 ms | 6.190 ms | 5.847 ms | 1.599 ms | 856.299 μs |
| maximum(norm) vec | Float64 512^3 | 336.516 ms | 171.415 ms | 105.972 ms | 92.751 ms | 119.194 ms | 71.373 ms | 55.867 ms | 56.637 ms | — | — |
| maximum(norm) vec | Float64 64^3 | 638.368 μs | 329.823 μs | 170.247 μs | 89.445 μs | 197.345 μs | 101.462 μs | 52.010 μs | 28.390 μs | 102.271 μs | 33.210 μs |
| mean spectral vec | Float32 128^3 | 69.141 ns | 70.276 ns | 70.963 ns | 70.261 ns | 71.866 ns | 72.826 ns | 73.592 ns | 72.022 ns | 84.967 μs | 12.840 μs |
| mean spectral vec | Float32 256^3 | 69.613 ns | 70.330 ns | 71.158 ns | 70.371 ns | 72.051 ns | 72.868 ns | 74.383 ns | 73.020 ns | 82.056 μs | 12.790 μs |
| mean spectral vec | Float32 512^3 | 69.234 ns | 71.054 ns | 71.069 ns | 70.932 ns | 72.308 ns | 75.150 ns | 76.622 ns | 73.985 ns | — | — |
| mean spectral vec | Float32 64^3 | 69.121 ns | 70.071 ns | 70.182 ns | 69.947 ns | 73.220 ns | 71.543 ns | 75.593 ns | 75.541 ns | 84.431 μs | 13.150 μs |
| mean spectral vec | Float64 128^3 | 71.070 ns | 71.867 ns | 73.049 ns | 72.324 ns | 76.788 ns | 78.394 ns | 79.217 ns | 75.652 ns | 83.967 μs | 13.100 μs |
| mean spectral vec | Float64 256^3 | 71.273 ns | 78.255 ns | 73.664 ns | 73.138 ns | 78.742 ns | 81.134 ns | 81.248 ns | 78.463 ns | 76.018 μs | 13.300 μs |
| mean spectral vec | Float64 512^3 | 71.664 ns | 73.460 ns | 74.082 ns | 72.926 ns | 79.338 ns | 82.651 ns | 84.589 ns | 81.494 ns | — | — |
| mean spectral vec | Float64 64^3 | 70.823 ns | 71.770 ns | 71.687 ns | 71.911 ns | 78.916 ns | 82.442 ns | 81.686 ns | 81.149 ns | 84.076 μs | 13.030 μs |
| mean vector | Float32 128^3 | 482.641 μs | 310.667 μs | 178.861 μs | 90.867 μs | 194.583 μs | 106.509 μs | 60.141 μs | 46.251 μs | 407.711 μs | 101.861 μs |
| mean vector | Float32 256^3 | 6.763 ms | 5.695 ms | 5.396 ms | 4.937 ms | 2.938 ms | 2.325 ms | 2.326 ms | 2.453 ms | 1.867 ms | 530.184 μs |
| mean vector | Float32 512^3 | 58.094 ms | 48.767 ms | 45.002 ms | 43.874 ms | 31.832 ms | 28.342 ms | 27.264 ms | 27.344 ms | — | — |
| mean vector | Float32 64^3 | 42.133 μs | 26.238 μs | 18.047 μs | 24.175 μs | 24.260 μs | 16.351 μs | 13.160 μs | 15.750 μs | 235.002 μs | 56.421 μs |
| mean vector | Float64 128^3 | 1.429 ms | 975.410 μs | 794.005 μs | 715.888 μs | 397.014 μs | 206.153 μs | 112.441 μs | 80.601 μs | 436.032 μs | 103.681 μs |
| mean vector | Float64 256^3 | 13.969 ms | 12.176 ms | 10.978 ms | 10.798 ms | 7.466 ms | 6.799 ms | 6.607 ms | 6.639 ms | 2.242 ms | 578.906 μs |
| mean vector | Float64 512^3 | 112.936 ms | 97.267 ms | 91.126 ms | 87.712 ms | 59.749 ms | 55.891 ms | 54.375 ms | 54.934 ms | — | — |
| mean vector | Float64 64^3 | 82.690 μs | 50.074 μs | 31.043 μs | 30.919 μs | 46.452 μs | 30.910 μs | 20.070 μs | 18.180 μs | 244.373 μs | 59.781 μs |
| mean(det) tensor | Float32 128^3 | 2.391 ms | 1.858 ms | 1.619 ms | 1.471 ms | 770.001 μs | 385.918 μs | 206.872 μs | 122.891 μs | 182.515 μs | 113.261 μs |
| mean(det) tensor | Float32 256^3 | 23.487 ms | 20.919 ms | 17.919 ms | 17.085 ms | 15.799 ms | 11.445 ms | 10.329 ms | 10.375 ms | 1.109 ms | 744.566 μs |
| mean(det) tensor | Float32 512^3 | 170.480 ms | 165.423 ms | 151.064 ms | 143.383 ms | 106.855 ms | 90.109 ms | 84.071 ms | 85.098 ms | — | — |
| mean(det) tensor | Float32 64^3 | 98.669 μs | 57.125 μs | 29.159 μs | 20.881 μs | 68.190 μs | 36.901 μs | 22.830 μs | 14.620 μs | 87.233 μs | 23.991 μs |
| mean(det) tensor | Float64 128^3 | 5.358 ms | 4.492 ms | 3.881 ms | 3.682 ms | 2.400 ms | 1.551 ms | 1.200 ms | 1.215 ms | 260.984 μs | 203.032 μs |
| mean(det) tensor | Float64 256^3 | 40.903 ms | 41.704 ms | 37.786 ms | 34.942 ms | 25.162 ms | 22.598 ms | 21.127 ms | 21.560 ms | 1.592 ms | 1.446 ms |
| mean(det) tensor | Float64 512^3 | 331.638 ms | 323.253 ms | 299.467 ms | 282.559 ms | 222.823 ms | 175.127 ms | 167.002 ms | 172.433 ms | — | — |
| mean(det) tensor | Float64 64^3 | 221.128 μs | 125.856 μs | 73.053 μs | 41.701 μs | 132.984 μs | 67.971 μs | 36.680 μs | 29.050 μs | 93.755 μs | 28.911 μs |
| mean(norm) vec | Float32 128^3 | 1.561 ms | 796.172 μs | 408.668 μs | 211.500 μs | 599.999 μs | 302.299 μs | 155.602 μs | 83.541 μs | 246.487 μs | 42.401 μs |
| mean(norm) vec | Float32 256^3 | 12.794 ms | 7.553 ms | 5.591 ms | 5.035 ms | 6.898 ms | 3.329 ms | 2.263 ms | 2.090 ms | 837.492 μs | 282.842 μs |
| mean(norm) vec | Float32 512^3 | 103.296 ms | 64.193 ms | 49.636 ms | 45.466 ms | 56.692 ms | 36.629 ms | 29.489 ms | 28.137 ms | — | — |
| mean(norm) vec | Float32 64^3 | 189.812 μs | 99.795 μs | 53.256 μs | 59.800 μs | 74.400 μs | 39.480 μs | 21.060 μs | 12.890 μs | 92.161 μs | 19.920 μs |
| mean(norm) vec | Float64 128^3 | 5.150 ms | 2.658 ms | 1.363 ms | 859.489 μs | 1.430 ms | 728.731 μs | 365.403 μs | 189.232 μs | 224.577 μs | 112.381 μs |
| mean(norm) vec | Float64 256^3 | 41.603 ms | 21.115 ms | 12.871 ms | 10.884 ms | 13.378 ms | 7.953 ms | 6.036 ms | 5.836 ms | 1.367 ms | 745.568 μs |
| mean(norm) vec | Float64 512^3 | 331.666 ms | 169.374 ms | 104.921 ms | 92.263 ms | 107.213 ms | 68.159 ms | 55.674 ms | 56.642 ms | — | — |
| mean(norm) vec | Float64 64^3 | 631.515 μs | 326.227 μs | 165.307 μs | 89.379 μs | 177.934 μs | 92.571 μs | 47.790 μs | 26.180 μs | 99.186 μs | 29.371 μs |
| mean(tr) tensor | Float32 128^3 | 383.753 μs | 249.344 μs | 141.769 μs | 71.857 μs | 191.162 μs | 95.870 μs | 51.340 μs | 36.861 μs | 146.107 μs | 39.711 μs |
| mean(tr) tensor | Float32 256^3 | 6.479 ms | 6.027 ms | 5.326 ms | 4.954 ms | 3.221 ms | 2.335 ms | 2.209 ms | 2.238 ms | 703.203 μs | 273.983 μs |
| mean(tr) tensor | Float32 512^3 | 52.170 ms | 50.593 ms | 47.170 ms | 45.005 ms | 33.297 ms | 28.981 ms | 27.593 ms | 27.967 ms | — | — |
| mean(tr) tensor | Float32 64^3 | 34.694 μs | 18.602 μs | 11.032 μs | 10.662 μs | 24.890 μs | 13.030 μs | 7.020 μs | 6.570 μs | 82.402 μs | 19.790 μs |
| mean(tr) tensor | Float64 128^3 | 1.240 ms | 956.573 μs | 809.477 μs | 703.590 μs | 381.214 μs | 198.083 μs | 101.941 μs | 72.781 μs | 161.262 μs | 50.581 μs |
| mean(tr) tensor | Float64 256^3 | 12.238 ms | 12.254 ms | 11.263 ms | 10.601 ms | 6.551 ms | 6.518 ms | 6.098 ms | 6.276 ms | 868.061 μs | 500.105 μs |
| mean(tr) tensor | Float64 512^3 | 103.483 ms | 98.420 ms | 93.789 ms | 89.037 ms | 75.440 ms | 57.447 ms | 55.027 ms | 56.735 ms | — | — |
| mean(tr) tensor | Float64 64^3 | 66.748 μs | 36.881 μs | 20.146 μs | 15.154 μs | 43.271 μs | 23.590 μs | 13.750 μs | 10.450 μs | 83.970 μs | 21.150 μs |
| radial_correlation vec | Float32 128^3 | 35.151 ms | 31.486 ms | 32.879 ms | 31.751 ms | 30.670 ms | 22.812 ms | 21.171 ms | 21.073 ms | 712.025 μs | 536.696 μs |
| radial_correlation vec | Float32 256^3 | 398.125 ms | 262.073 ms | 236.578 ms | 259.450 ms | 301.124 ms | 229.578 ms | 173.510 ms | 157.348 ms | 10.100 ms | 6.288 ms |
| radial_correlation vec | Float32 512^3 | 3.394 s | 2.295 s | 1.816 s | 1.610 s | 2.800 s | 1.764 s | 1.289 s | 1.122 s | — | — |
| radial_correlation vec | Float32 64^3 | 4.219 ms | 5.035 ms | 5.348 ms | 5.679 ms | 3.505 ms | 3.317 ms | 3.594 ms | 3.614 ms | 228.975 μs | 152.991 μs |
| radial_correlation vec | Float64 128^3 | 43.432 ms | 52.445 ms | 38.468 ms | 35.521 ms | 39.079 ms | 28.801 ms | 25.189 ms | 29.011 ms | 36.307 ms | 1.872 ms |
| radial_correlation vec | Float64 256^3 | 560.709 ms | 401.741 ms | 322.978 ms | 332.686 ms | 473.006 ms | 371.201 ms | 253.284 ms | 236.277 ms | 143.483 ms | 14.582 ms |
| radial_correlation vec | Float64 512^3 | 5.447 s | 3.601 s | 2.808 s | 2.482 s | 4.274 s | 2.727 s | 2.000 s | 1.699 s | — | — |
| radial_correlation vec | Float64 64^3 | 5.210 ms | 4.824 ms | 5.190 ms | 5.392 ms | 3.836 ms | 3.287 ms | 3.355 ms | 3.222 ms | 12.815 ms | 255.802 μs |
| radial_spectrum vec | Float32 128^3 | 7.486 ms | 6.712 ms | 8.332 ms | 7.899 ms | 6.330 ms | 4.761 ms | 5.999 ms | 6.061 ms | 319.559 μs | 171.762 μs |
| radial_spectrum vec | Float32 256^3 | 59.596 ms | 45.185 ms | 45.037 ms | 43.598 ms | 50.092 ms | 34.074 ms | 31.784 ms | 29.978 ms | 939.271 μs | 821.928 μs |
| radial_spectrum vec | Float32 512^3 | 476.201 ms | 349.437 ms | 262.054 ms | 230.205 ms | 399.037 ms | 239.533 ms | 180.748 ms | 153.007 ms | — | — |
| radial_spectrum vec | Float32 64^3 | 977.725 μs | 1.357 ms | 1.587 ms | 1.686 ms | 821.540 μs | 904.233 μs | 1.228 ms | 1.392 ms | 218.585 μs | 71.771 μs |
| radial_spectrum vec | Float64 128^3 | 7.572 ms | 5.542 ms | 6.097 ms | 5.876 ms | 6.535 ms | 4.583 ms | 4.357 ms | 4.367 ms | 17.266 ms | 251.633 μs |
| radial_spectrum vec | Float64 256^3 | 60.277 ms | 43.936 ms | 35.197 ms | 31.135 ms | 51.987 ms | 32.482 ms | 25.271 ms | 22.755 ms | 55.432 ms | 1.135 ms |
| radial_spectrum vec | Float64 512^3 | 490.738 ms | 337.787 ms | 219.470 ms | 168.824 ms | 414.326 ms | 251.233 ms | 167.417 ms | 124.519 ms | — | — |
| radial_spectrum vec | Float64 64^3 | 974.096 μs | 912.629 μs | 1.061 ms | 1.067 ms | 858.022 μs | 699.219 μs | 838.873 μs | 922.618 μs | 6.966 ms | 76.991 μs |
| reality_residual scalar | Float32 128^3 | 213.743 μs | 218.943 μs | 218.008 μs | 218.007 μs | 169.582 μs | 167.078 μs | 167.182 μs | 167.611 μs | 243.277 μs | 82.741 μs |
| reality_residual scalar | Float32 256^3 | 984.448 μs | 986.522 μs | 990.420 μs | 984.565 μs | 692.125 μs | 677.145 μs | 686.847 μs | 687.846 μs | 223.046 μs | 81.121 μs |
| reality_residual scalar | Float32 512^3 | 7.867 ms | 8.057 ms | 8.058 ms | 8.106 ms | 2.783 ms | 2.752 ms | 2.750 ms | 2.787 ms | — | — |
| reality_residual scalar | Float32 64^3 | 49.487 μs | 49.595 μs | 49.710 μs | 49.914 μs | 41.230 μs | 41.351 μs | 41.890 μs | 40.830 μs | 231.816 μs | 82.300 μs |
| reality_residual scalar | Float64 128^3 | 358.359 μs | 359.414 μs | 359.712 μs | 360.497 μs | 346.273 μs | 345.966 μs | 348.003 μs | 352.074 μs | 238.392 μs | 95.862 μs |
| reality_residual scalar | Float64 256^3 | 1.618 ms | 1.585 ms | 1.628 ms | 1.591 ms | 1.416 ms | 1.416 ms | 1.423 ms | 1.409 ms | 242.901 μs | 97.931 μs |
| reality_residual scalar | Float64 512^3 | 13.108 ms | 12.537 ms | 12.435 ms | 12.722 ms | 5.798 ms | 5.855 ms | 5.700 ms | 5.869 ms | — | — |
| reality_residual scalar | Float64 64^3 | 78.306 μs | 78.560 μs | 79.120 μs | 79.472 μs | 85.242 μs | 85.321 μs | 85.160 μs | 85.671 μs | 231.729 μs | 95.921 μs |
| reality_residual vector | Float32 128^3 | 797.970 μs | 802.071 μs | 805.810 μs | 802.633 μs | 648.750 μs | 649.106 μs | 647.086 μs | 647.806 μs | 248.532 μs | 88.551 μs |
| reality_residual vector | Float32 256^3 | 5.641 ms | 5.234 ms | 5.167 ms | 5.671 ms | 2.606 ms | 2.622 ms | 2.610 ms | 2.613 ms | 292.628 μs | 92.610 μs |
| reality_residual vector | Float32 512^3 | 34.370 ms | 33.639 ms | 33.893 ms | 34.058 ms | 16.162 ms | 16.596 ms | 16.762 ms | 17.179 ms | — | — |
| reality_residual vector | Float32 64^3 | 186.153 μs | 183.949 μs | 185.382 μs | 186.842 μs | 162.210 μs | 160.872 μs | 160.191 μs | 161.762 μs | 245.317 μs | 84.071 μs |
| reality_residual vector | Float64 128^3 | 1.265 ms | 1.263 ms | 1.274 ms | 1.266 ms | 1.249 ms | 1.247 ms | 1.239 ms | 1.250 ms | 254.129 μs | 100.891 μs |
| reality_residual vector | Float64 256^3 | 8.667 ms | 8.748 ms | 8.526 ms | 9.556 ms | 5.034 ms | 5.015 ms | 5.042 ms | 5.025 ms | 285.748 μs | 119.131 μs |
| reality_residual vector | Float64 512^3 | 47.947 ms | 48.343 ms | 48.199 ms | 48.095 ms | 35.476 ms | 35.356 ms | 35.350 ms | 35.273 ms | — | — |
| reality_residual vector | Float64 64^3 | 270.954 μs | 273.350 μs | 273.271 μs | 275.105 μs | 308.618 μs | 308.644 μs | 309.571 μs | 309.663 μs | 243.844 μs | 97.261 μs |
| var scalar | Float32 128^3 | 239.652 μs | 133.984 μs | 67.287 μs | 43.435 μs | 132.862 μs | 73.330 μs | 41.770 μs | 26.660 μs | 268.699 μs | 64.721 μs |
| var scalar | Float32 256^3 | 4.956 ms | 3.328 ms | 2.624 ms | 2.438 ms | 1.195 ms | 563.854 μs | 311.983 μs | 197.602 μs | 1.221 ms | 351.623 μs |
| var scalar | Float32 512^3 | 40.566 ms | 32.049 ms | 29.920 ms | 29.032 ms | 25.429 ms | 20.962 ms | 17.962 ms | 18.162 ms | — | — |
| var scalar | Float32 64^3 | 25.076 μs | 16.319 μs | 11.845 μs | 15.311 μs | 14.800 μs | 8.830 μs | 7.270 μs | 9.141 μs | 150.346 μs | 36.551 μs |
| var scalar | Float64 128^3 | 454.598 μs | 267.987 μs | 137.690 μs | 80.483 μs | 249.912 μs | 131.122 μs | 70.940 μs | 48.690 μs | 315.483 μs | 66.581 μs |
| var scalar | Float64 256^3 | 8.736 ms | 7.554 ms | 6.595 ms | 6.133 ms | 4.247 ms | 2.445 ms | 1.770 ms | 1.785 ms | 1.549 ms | 385.974 μs |
| var scalar | Float64 512^3 | 74.782 ms | 64.406 ms | 60.963 ms | 58.476 ms | 45.104 ms | 38.553 ms | 36.555 ms | 36.229 ms | — | — |
| var scalar | Float64 64^3 | 52.096 μs | 26.975 μs | 18.050 μs | 16.950 μs | 30.531 μs | 16.731 μs | 10.990 μs | 10.970 μs | 168.107 μs | 39.321 μs |
| var spectral scalar | Float32 128^3 | 130.904 μs | 93.990 μs | 60.903 μs | 55.884 μs | 92.041 μs | 59.480 μs | 42.190 μs | 39.811 μs | 257.121 μs | 67.881 μs |
| var spectral scalar | Float32 256^3 | 2.217 ms | 1.770 ms | 1.577 ms | 1.445 ms | 758.435 μs | 399.083 μs | 292.923 μs | 240.273 μs | 468.654 μs | 151.741 μs |
| var spectral scalar | Float32 512^3 | 19.848 ms | 17.694 ms | 16.980 ms | 16.349 ms | 12.664 ms | 10.499 ms | 10.644 ms | 10.784 ms | — | — |
| var spectral scalar | Float32 64^3 | 16.863 μs | 12.248 μs | 9.897 μs | 11.313 μs | 11.170 μs | 7.940 μs | 7.320 μs | 9.480 μs | 211.936 μs | 57.530 μs |
| var spectral scalar | Float64 128^3 | 250.977 μs | 181.594 μs | 113.706 μs | 87.324 μs | 145.901 μs | 87.841 μs | 60.720 μs | 58.210 μs | 269.779 μs | 68.021 μs |
| var spectral scalar | Float64 256^3 | 4.605 ms | 3.946 ms | 3.674 ms | 3.391 ms | 2.112 ms | 1.347 ms | 1.080 ms | 1.127 ms | 581.010 μs | 233.392 μs |
| var spectral scalar | Float64 512^3 | 40.653 ms | 34.727 ms | 33.266 ms | 31.667 ms | 20.942 ms | 20.525 ms | 20.427 ms | 20.566 ms | — | — |
| var spectral scalar | Float64 64^3 | 30.342 μs | 19.188 μs | 13.898 μs | 13.840 μs | 19.750 μs | 12.151 μs | 9.380 μs | 10.960 μs | 235.839 μs | 57.921 μs |
| weighted_inner vec | Float32 128^3 | 1.662 ms | 892.709 μs | 500.096 μs | 367.242 μs | 1.356 ms | 679.315 μs | 346.413 μs | 178.372 μs | 260.415 μs | 75.091 μs |
| weighted_inner vec | Float32 256^3 | 15.948 ms | 12.356 ms | 10.879 ms | 10.025 ms | 11.124 ms | 5.664 ms | 3.501 ms | 3.550 ms | 1.449 ms | 549.995 μs |
| weighted_inner vec | Float32 512^3 | 130.365 ms | 106.851 ms | 95.918 ms | 89.345 ms | 92.283 ms | 63.721 ms | 54.328 ms | 54.422 ms | — | — |
| weighted_inner vec | Float32 64^3 | 218.836 μs | 235.411 μs | 219.880 μs | 220.153 μs | 185.110 μs | 190.073 μs | 184.751 μs | 186.171 μs | 120.520 μs | 26.220 μs |
| weighted_inner vec | Float64 128^3 | 3.063 ms | 2.420 ms | 1.867 ms | 1.575 ms | 1.400 ms | 729.640 μs | 366.083 μs | 189.562 μs | 302.167 μs | 97.831 μs |
| weighted_inner vec | Float64 256^3 | 29.371 ms | 25.216 ms | 22.985 ms | 21.528 ms | 15.539 ms | 11.674 ms | 10.238 ms | 10.186 ms | 1.825 ms | 982.701 μs |
| weighted_inner vec | Float64 512^3 | 241.161 ms | 207.671 ms | 191.184 ms | 177.627 ms | 114.123 ms | 113.570 ms | 112.409 ms | 112.381 ms | — | — |
| weighted_inner vec | Float64 64^3 | 252.268 μs | 251.484 μs | 251.917 μs | 251.552 μs | 193.876 μs | 199.902 μs | 193.971 μs | 195.871 μs | 124.601 μs | 28.260 μs |
| weighted_inner vec.vec | Float32 128^3 | 2.092 ms | 1.572 ms | 1.253 ms | 1.090 ms | 1.382 ms | 725.906 μs | 354.744 μs | 187.442 μs | 263.406 μs | 90.691 μs |
| weighted_inner vec.vec | Float32 256^3 | 21.621 ms | 18.964 ms | 17.365 ms | 16.185 ms | 12.449 ms | 8.520 ms | 7.220 ms | 7.331 ms | 1.448 ms | 745.297 μs |
| weighted_inner vec.vec | Float32 512^3 | 187.332 ms | 163.004 ms | 145.978 ms | 135.174 ms | 100.047 ms | 88.309 ms | 84.957 ms | 84.587 ms | — | — |
| weighted_inner vec.vec | Float32 64^3 | 219.543 μs | 220.854 μs | 236.257 μs | 221.277 μs | 188.500 μs | 190.073 μs | 192.161 μs | 195.261 μs | 117.471 μs | 26.430 μs |
| weighted_inner vec.vec | Float64 128^3 | 4.597 ms | 4.023 ms | 3.541 ms | 3.164 ms | 1.950 ms | 1.050 ms | 654.145 μs | 530.435 μs | 302.544 μs | 178.982 μs |
| weighted_inner vec.vec | Float64 256^3 | 43.119 ms | 38.744 ms | 35.527 ms | 33.349 ms | 23.303 ms | 19.212 ms | 18.047 ms | 17.798 ms | 1.846 ms | 1.461 ms |
| weighted_inner vec.vec | Float64 512^3 | 341.644 ms | 311.669 ms | 288.879 ms | 267.629 ms | 174.186 ms | 173.547 ms | 170.675 ms | 169.914 ms | — | — |
| weighted_inner vec.vec | Float64 64^3 | 281.112 μs | 278.768 μs | 303.706 μs | 278.558 μs | 202.745 μs | 210.083 μs | 203.761 μs | 211.312 μs | 122.985 μs | 28.500 μs |
| weighted_inner x3 fused | Float32 128^3 | 6.108 ms | 3.128 ms | 1.594 ms | 814.594 μs | 5.046 ms | 2.516 ms | 1.261 ms | 636.996 μs | 327.755 μs | 121.151 μs |
| weighted_inner x3 fused | Float32 256^3 | 47.027 ms | 23.970 ms | 12.313 ms | 6.401 ms | 38.474 ms | 19.241 ms | 9.941 ms | 5.001 ms | 1.918 ms | 865.128 μs |
| weighted_inner x3 fused | Float32 512^3 | 367.060 ms | 186.553 ms | 95.774 ms | 51.866 ms | 317.720 ms | 152.538 ms | 79.181 ms | 39.378 ms | — | — |
| weighted_inner x3 fused | Float32 64^3 | 826.607 μs | 830.956 μs | 811.360 μs | 799.010 μs | 655.700 μs | 634.320 μs | 654.985 μs | 651.015 μs | 134.183 μs | 35.030 μs |
| weighted_inner x3 fused | Float64 128^3 | 6.265 ms | 3.160 ms | 1.653 ms | 967.902 μs | 5.059 ms | 2.486 ms | 1.269 ms | 640.686 μs | 508.994 μs | 201.763 μs |
| weighted_inner x3 fused | Float64 256^3 | 47.611 ms | 24.160 ms | 13.594 ms | 11.356 ms | 39.872 ms | 19.506 ms | 9.933 ms | 5.759 ms | 3.360 ms | 1.377 ms |
| weighted_inner x3 fused | Float64 512^3 | 366.249 ms | 187.237 ms | 107.897 ms | 91.901 ms | 319.695 ms | 156.564 ms | 80.534 ms | 55.082 ms | — | — |
| weighted_inner x3 fused | Float64 64^3 | 842.391 μs | 803.162 μs | 808.551 μs | 820.538 μs | 660.878 μs | 640.369 μs | 658.333 μs | 653.816 μs | 151.155 μs | 48.651 μs |
| weighted_inner x3 separate | Float32 128^3 | 8.047 ms | 4.131 ms | 2.146 ms | 1.122 ms | 6.226 ms | 2.966 ms | 1.567 ms | 801.548 μs | 787.266 μs | 262.102 μs |
| weighted_inner x3 separate | Float32 256^3 | 60.834 ms | 32.095 ms | 19.224 ms | 16.200 ms | 46.907 ms | 23.320 ms | 12.366 ms | 6.865 ms | 4.850 ms | 1.715 ms |
| weighted_inner x3 separate | Float32 512^3 | 467.438 ms | 247.507 ms | 155.081 ms | 139.185 ms | 388.279 ms | 185.619 ms | 104.210 ms | 82.350 ms | — | — |
| weighted_inner x3 separate | Float32 64^3 | 1.056 ms | 1.057 ms | 1.056 ms | 1.056 ms | 829.101 μs | 782.031 μs | 830.275 μs | 828.737 μs | 349.174 μs | 86.551 μs |
| weighted_inner x3 separate | Float64 128^3 | 9.389 ms | 5.085 ms | 3.254 ms | 2.576 ms | 6.207 ms | 2.990 ms | 1.566 ms | 802.748 μs | 1.025 ms | 317.124 μs |
| weighted_inner x3 separate | Float64 256^3 | 74.079 ms | 45.374 ms | 35.316 ms | 32.981 ms | 52.280 ms | 26.461 ms | 17.819 ms | 16.772 ms | 6.264 ms | 2.073 ms |
| weighted_inner x3 separate | Float64 512^3 | 599.118 ms | 368.754 ms | 285.475 ms | 267.885 ms | 402.600 ms | 219.908 ms | 164.679 ms | 164.141 ms | — | — |
| weighted_inner x3 separate | Float64 64^3 | 1.113 ms | 1.113 ms | 1.113 ms | 1.114 ms | 818.981 μs | 812.630 μs | 810.723 μs | 811.997 μs | 375.382 μs | 95.621 μs |

## storage

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| adapt multipliers | Float32 128^3 | — | — | — | — | — | — | — | — | 138.471 μs | 12.130 μs |
| adapt multipliers | Float32 256^3 | — | — | — | — | — | — | — | — | 153.250 μs | 13.050 μs |
| adapt multipliers | Float32 512^3 | — | — | — | — | — | — | — | — | 153.374 μs | — |
| adapt multipliers | Float32 64^3 | — | — | — | — | — | — | — | — | 146.466 μs | 12.770 μs |
| adapt multipliers | Float64 128^3 | — | — | — | — | — | — | — | — | 149.081 μs | 12.300 μs |
| adapt multipliers | Float64 256^3 | — | — | — | — | — | — | — | — | 148.469 μs | 13.190 μs |
| adapt multipliers | Float64 64^3 | — | — | — | — | — | — | — | — | 142.844 μs | 12.710 μs |
| adapt plans (rebuild) | Float32 128^3 | — | — | — | — | — | — | — | — | 17.967 μs | 8.300 μs |
| adapt plans (rebuild) | Float32 256^3 | — | — | — | — | — | — | — | — | 64.793 μs | 60.761 μs |
| adapt plans (rebuild) | Float32 512^3 | — | — | — | — | — | — | — | — | 67.511 μs | — |
| adapt plans (rebuild) | Float32 64^3 | — | — | — | — | — | — | — | — | 11.537 μs | 7.950 μs |
| adapt plans (rebuild) | Float64 128^3 | — | — | — | — | — | — | — | — | 21.871 μs | 9.150 μs |
| adapt plans (rebuild) | Float64 256^3 | — | — | — | — | — | — | — | — | 62.267 μs | 49.631 μs |
| adapt plans (rebuild) | Float64 64^3 | — | — | — | — | — | — | — | — | 12.024 μs | 7.540 μs |
| adapt to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 672.029 μs | 307.823 μs |
| adapt to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.603 ms | 2.446 ms |
| adapt to device scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 42.777 ms | — |
| adapt to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 124.403 μs | 59.761 μs |
| adapt to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.342 ms | 592.927 μs |
| adapt to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 11.259 ms | 6.159 ms |
| adapt to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 172.713 μs | 93.961 μs |
| adapt to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.999 ms | 877.799 μs |
| adapt to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 16.397 ms | 9.303 ms |
| adapt to device vector | Float32 512^3 | — | — | — | — | — | — | — | — | 126.184 ms | — |
| adapt to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 258.890 μs | 129.241 μs |
| adapt to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 4.268 ms | 1.765 ms |
| adapt to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 32.157 ms | 19.863 ms |
| adapt to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 512.232 μs | 236.562 μs |
| adapt to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 512.599 μs | 418.014 μs |
| adapt to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 12.751 ms | 11.806 ms |
| adapt to host scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 92.981 ms | — |
| adapt to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 114.163 μs | 62.421 μs |
| adapt to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.027 ms | 830.580 μs |
| adapt to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 23.696 ms | 23.547 ms |
| adapt to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 130.375 μs | 114.541 μs |
| adapt to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.526 ms | 1.235 ms |
| adapt to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 35.027 ms | 35.701 ms |
| adapt to host vector | Float32 512^3 | — | — | — | — | — | — | — | — | 280.672 ms | — |
| adapt to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 195.252 μs | 163.571 μs |
| adapt to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 9.058 ms | 8.550 ms |
| adapt to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 69.022 ms | 71.548 ms |
| adapt to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 384.091 μs | 317.933 μs |
| adapt to own family (identity) | Float32 128^3 | — | — | — | — | — | — | — | — | 147.659 ns | 129.596 ns |
| adapt to own family (identity) | Float32 256^3 | — | — | — | — | — | — | — | — | 147.047 ns | 129.900 ns |
| adapt to own family (identity) | Float32 512^3 | — | — | — | — | — | — | — | — | 158.228 ns | — |
| adapt to own family (identity) | Float32 64^3 | — | — | — | — | — | — | — | — | 147.184 ns | 129.213 ns |
| adapt to own family (identity) | Float64 128^3 | — | — | — | — | — | — | — | — | 147.794 ns | 124.979 ns |
| adapt to own family (identity) | Float64 256^3 | — | — | — | — | — | — | — | — | 146.425 ns | 125.523 ns |
| adapt to own family (identity) | Float64 64^3 | — | — | — | — | — | — | — | — | 146.381 ns | 127.543 ns |
| adapt! to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 666.883 μs | 303.914 μs |
| adapt! to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.233 ms | 2.433 ms |
| adapt! to device scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 42.054 ms | — |
| adapt! to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 113.354 μs | 57.770 μs |
| adapt! to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.336 ms | 586.587 μs |
| adapt! to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 10.414 ms | 6.046 ms |
| adapt! to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 168.115 μs | 91.471 μs |
| adapt! to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.998 ms | 874.680 μs |
| adapt! to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 15.632 ms | 9.085 ms |
| adapt! to device vector | Float32 512^3 | — | — | — | — | — | — | — | — | 125.463 ms | — |
| adapt! to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 253.874 μs | 126.852 μs |
| adapt! to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.923 ms | 1.745 ms |
| adapt! to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 31.337 ms | 18.395 ms |
| adapt! to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 507.358 μs | 232.723 μs |
| adapt! to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 525.143 μs | 416.065 μs |
| adapt! to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 4.239 ms | 3.277 ms |
| adapt! to host scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 33.264 ms | — |
| adapt! to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 103.282 μs | 62.111 μs |
| adapt! to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.045 ms | 825.959 μs |
| adapt! to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 8.118 ms | 6.571 ms |
| adapt! to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 130.692 μs | 113.371 μs |
| adapt! to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.516 ms | 1.233 ms |
| adapt! to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 12.544 ms | 9.832 ms |
| adapt! to host vector | Float32 512^3 | — | — | — | — | — | — | — | — | 99.702 ms | — |
| adapt! to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 198.267 μs | 164.372 μs |
| adapt! to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.060 ms | 2.462 ms |
| adapt! to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 24.438 ms | 19.712 ms |
| adapt! to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 385.345 μs | 315.124 μs |

## resolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| embed_modes! scalar block | Float32 128^3 | — | — | — | — | 19.680 μs | 19.650 μs | 19.611 μs | 19.590 μs | — | 7.660 μs |
| embed_modes! scalar block | Float32 256^3 | — | — | — | — | 19.681 μs | 19.660 μs | 19.610 μs | 19.570 μs | — | 7.767 μs |
| embed_modes! scalar block | Float32 512^3 | — | — | — | — | 19.660 μs | 19.670 μs | 19.600 μs | 19.601 μs | — | — |
| embed_modes! scalar block | Float32 64^3 | — | — | — | — | 19.660 μs | 19.650 μs | 19.610 μs | 19.651 μs | — | 7.700 μs |
| embed_modes! scalar block | Float64 128^3 | — | — | — | — | 19.451 μs | 19.440 μs | 19.430 μs | 19.470 μs | — | 7.990 μs |
| embed_modes! scalar block | Float64 256^3 | — | — | — | — | 19.440 μs | 19.410 μs | 19.440 μs | 19.410 μs | — | 8.053 μs |
| embed_modes! scalar block | Float64 512^3 | — | — | — | — | 19.450 μs | 19.440 μs | 19.420 μs | 19.430 μs | — | — |
| embed_modes! scalar block | Float64 64^3 | — | — | — | — | 19.450 μs | 19.450 μs | 19.430 μs | 19.441 μs | — | 7.850 μs |
| embed_modes! scalar half | Float32 128^3 | — | — | — | — | 1.184 ms | 595.507 μs | 297.513 μs | 150.532 μs | — | 9.260 μs |
| embed_modes! scalar half | Float32 256^3 | — | — | — | — | 9.362 ms | 4.692 ms | 2.335 ms | 1.169 ms | — | 25.661 μs |
| embed_modes! scalar half | Float32 512^3 | — | — | — | — | 74.423 ms | 37.249 ms | 18.537 ms | 9.288 ms | — | — |
| embed_modes! scalar half | Float32 64^3 | — | — | — | — | 150.310 μs | 77.311 μs | 39.700 μs | 21.651 μs | — | 7.767 μs |
| embed_modes! scalar half | Float64 128^3 | — | — | — | — | 1.153 ms | 579.679 μs | 292.453 μs | 148.301 μs | — | 10.480 μs |
| embed_modes! scalar half | Float64 256^3 | — | — | — | — | 9.098 ms | 4.563 ms | 2.289 ms | 1.142 ms | — | 28.231 μs |
| embed_modes! scalar half | Float64 512^3 | — | — | — | — | 72.422 ms | 36.284 ms | 18.164 ms | 9.100 ms | — | — |
| embed_modes! scalar half | Float64 64^3 | — | — | — | — | 147.538 μs | 75.901 μs | 38.980 μs | 21.410 μs | — | 7.920 μs |
| embed_modes! vector accumulate block | Float32 128^3 | — | — | — | — | 58.561 μs | 58.580 μs | 58.531 μs | 58.580 μs | — | 7.750 μs |
| embed_modes! vector accumulate block | Float32 256^3 | — | — | — | — | 58.671 μs | 58.621 μs | 58.680 μs | 58.480 μs | — | 7.877 μs |
| embed_modes! vector accumulate block | Float32 512^3 | — | — | — | — | 58.540 μs | 58.610 μs | 58.600 μs | 58.621 μs | — | — |
| embed_modes! vector accumulate block | Float32 64^3 | — | — | — | — | 58.560 μs | 58.591 μs | 58.570 μs | 58.420 μs | — | 7.867 μs |
| embed_modes! vector accumulate block | Float64 128^3 | — | — | — | — | 58.510 μs | 58.171 μs | 58.190 μs | 58.520 μs | — | 8.070 μs |
| embed_modes! vector accumulate block | Float64 256^3 | — | — | — | — | 58.561 μs | 58.161 μs | 58.180 μs | 58.091 μs | — | 8.050 μs |
| embed_modes! vector accumulate block | Float64 512^3 | — | — | — | — | 58.669 μs | 58.270 μs | 58.240 μs | 58.280 μs | — | — |
| embed_modes! vector accumulate block | Float64 64^3 | — | — | — | — | 58.480 μs | 58.130 μs | 58.001 μs | 58.140 μs | — | 8.020 μs |
| embed_modes! vector block | Float32 128^3 | — | — | — | — | 59.190 μs | 59.110 μs | 59.151 μs | 59.121 μs | — | 7.864 μs |
| embed_modes! vector block | Float32 256^3 | — | — | — | — | 59.241 μs | 59.150 μs | 59.200 μs | 59.110 μs | — | 7.807 μs |
| embed_modes! vector block | Float32 512^3 | — | — | — | — | 59.091 μs | 59.160 μs | 59.170 μs | 59.120 μs | — | — |
| embed_modes! vector block | Float32 64^3 | — | — | — | — | 59.080 μs | 59.111 μs | 59.110 μs | 58.951 μs | — | 7.817 μs |
| embed_modes! vector block | Float64 128^3 | — | — | — | — | 58.210 μs | 58.381 μs | 58.460 μs | 58.240 μs | — | 8.020 μs |
| embed_modes! vector block | Float64 256^3 | — | — | — | — | 58.271 μs | 58.430 μs | 58.431 μs | 58.370 μs | — | 8.180 μs |
| embed_modes! vector block | Float64 512^3 | — | — | — | — | 58.239 μs | 58.460 μs | 58.450 μs | 58.391 μs | — | — |
| embed_modes! vector block | Float64 64^3 | — | — | — | — | 58.242 μs | 58.371 μs | 58.390 μs | 58.440 μs | — | 8.041 μs |
| embed_modes! vector half | Float32 128^3 | — | — | — | — | 3.560 ms | 1.784 ms | 893.879 μs | 448.975 μs | — | 14.150 μs |
| embed_modes! vector half | Float32 256^3 | — | — | — | — | 28.079 ms | 14.072 ms | 7.041 ms | 3.528 ms | — | 72.631 μs |
| embed_modes! vector half | Float32 512^3 | — | — | — | — | 223.762 ms | 111.964 ms | 56.142 ms | 28.127 ms | — | — |
| embed_modes! vector half | Float32 64^3 | — | — | — | — | 451.951 μs | 228.893 μs | 115.501 μs | 59.211 μs | — | 7.923 μs |
| embed_modes! vector half | Float64 128^3 | — | — | — | — | 3.461 ms | 1.742 ms | 872.077 μs | 436.744 μs | — | 15.741 μs |
| embed_modes! vector half | Float64 256^3 | — | — | — | — | 27.270 ms | 13.711 ms | 6.868 ms | 3.445 ms | — | 165.302 μs |
| embed_modes! vector half | Float64 512^3 | — | — | — | — | 217.066 ms | 109.563 ms | 54.832 ms | 27.541 ms | — | — |
| embed_modes! vector half | Float64 64^3 | — | — | — | — | 441.930 μs | 224.513 μs | 113.171 μs | 58.621 μs | — | 8.260 μs |
| extract_modes! scalar block | Float32 128^3 | — | — | — | — | 19.710 μs | 19.669 μs | 19.660 μs | 19.700 μs | — | 7.697 μs |
| extract_modes! scalar block | Float32 256^3 | — | — | — | — | 19.711 μs | 19.641 μs | 19.640 μs | 19.640 μs | — | 7.503 μs |
| extract_modes! scalar block | Float32 512^3 | — | — | — | — | 19.730 μs | 19.650 μs | 19.640 μs | 19.710 μs | — | — |
| extract_modes! scalar block | Float32 64^3 | — | — | — | — | 19.690 μs | 19.670 μs | 19.650 μs | 19.720 μs | — | 7.583 μs |
| extract_modes! scalar block | Float64 128^3 | — | — | — | — | 19.410 μs | 19.380 μs | 19.421 μs | 19.410 μs | — | 7.800 μs |
| extract_modes! scalar block | Float64 256^3 | — | — | — | — | 19.410 μs | 19.390 μs | 19.420 μs | 19.440 μs | — | 7.953 μs |
| extract_modes! scalar block | Float64 512^3 | — | — | — | — | 19.389 μs | 19.410 μs | 19.450 μs | 19.450 μs | — | — |
| extract_modes! scalar block | Float64 64^3 | — | — | — | — | 19.390 μs | 19.411 μs | 19.440 μs | 19.390 μs | — | 7.950 μs |
| extract_modes! scalar half | Float32 128^3 | — | — | — | — | 1.184 ms | 592.287 μs | 298.043 μs | 151.662 μs | — | 9.160 μs |
| extract_modes! scalar half | Float32 256^3 | — | — | — | — | 9.345 ms | 4.657 ms | 2.333 ms | 1.169 ms | — | 25.680 μs |
| extract_modes! scalar half | Float32 512^3 | — | — | — | — | 74.370 ms | 36.978 ms | 18.531 ms | 9.333 ms | — | — |
| extract_modes! scalar half | Float32 64^3 | — | — | — | — | 150.430 μs | 77.011 μs | 39.610 μs | 21.760 μs | — | 7.703 μs |
| extract_modes! scalar half | Float64 128^3 | — | — | — | — | 1.151 ms | 578.499 μs | 292.383 μs | 147.641 μs | — | 10.401 μs |
| extract_modes! scalar half | Float64 256^3 | — | — | — | — | 9.090 ms | 4.547 ms | 2.290 ms | 1.151 ms | — | 28.330 μs |
| extract_modes! scalar half | Float64 512^3 | — | — | — | — | 72.376 ms | 36.225 ms | 18.780 ms | 9.517 ms | — | — |
| extract_modes! scalar half | Float64 64^3 | — | — | — | — | 147.208 μs | 76.161 μs | 38.970 μs | 21.360 μs | — | 8.007 μs |
| extract_modes! vector block | Float32 128^3 | — | — | — | — | 58.991 μs | 58.990 μs | 59.031 μs | 59.200 μs | — | 7.727 μs |
| extract_modes! vector block | Float32 256^3 | — | — | — | — | 59.021 μs | 59.060 μs | 58.970 μs | 59.290 μs | — | 7.697 μs |
| extract_modes! vector block | Float32 512^3 | — | — | — | — | 59.041 μs | 59.080 μs | 59.010 μs | 59.110 μs | — | — |
| extract_modes! vector block | Float32 64^3 | — | — | — | — | 58.960 μs | 59.061 μs | 58.940 μs | 59.141 μs | — | 7.700 μs |
| extract_modes! vector block | Float64 128^3 | — | — | — | — | 58.421 μs | 58.411 μs | 58.481 μs | 58.400 μs | — | 7.920 μs |
| extract_modes! vector block | Float64 256^3 | — | — | — | — | 58.461 μs | 58.370 μs | 58.430 μs | 58.400 μs | — | 7.940 μs |
| extract_modes! vector block | Float64 512^3 | — | — | — | — | 58.489 μs | 58.461 μs | 58.571 μs | 58.531 μs | — | — |
| extract_modes! vector block | Float64 64^3 | — | — | — | — | 58.341 μs | 58.370 μs | 58.400 μs | 58.370 μs | — | 8.010 μs |
| extract_modes! vector half | Float32 128^3 | — | — | — | — | 3.533 ms | 1.775 ms | 886.509 μs | 446.944 μs | — | 14.131 μs |
| extract_modes! vector half | Float32 256^3 | — | — | — | — | 27.887 ms | 13.966 ms | 6.993 ms | 3.529 ms | — | 70.470 μs |
| extract_modes! vector half | Float32 512^3 | — | — | — | — | 222.308 ms | 111.305 ms | 55.819 ms | 28.012 ms | — | — |
| extract_modes! vector half | Float32 64^3 | — | — | — | — | 449.930 μs | 228.074 μs | 115.041 μs | 59.631 μs | — | 7.807 μs |
| extract_modes! vector half | Float64 128^3 | — | — | — | — | 3.460 ms | 1.738 ms | 871.917 μs | 438.934 μs | — | 16.001 μs |
| extract_modes! vector half | Float64 256^3 | — | — | — | — | 27.381 ms | 13.770 ms | 6.909 ms | 3.459 ms | — | 151.662 μs |
| extract_modes! vector half | Float64 512^3 | — | — | — | — | 227.988 ms | 113.178 ms | 57.450 ms | 29.302 ms | — | — |
| extract_modes! vector half | Float64 64^3 | — | — | — | — | 443.754 μs | 224.803 μs | 113.070 μs | 58.631 μs | — | 8.310 μs |

## Triage — the born-slow scan

Two questions no per-row history can answer (finding (ag)): does a threaded operation actually scale, and is a row wildly slower than its class peers at the same workload. Flags are QUESTIONS, not verdicts — a `known` row carries its recorded reason, and an unexplained one is closed by a fix or by a recorded reason, never by deleting the row. Thresholds: flat means under 1.1x speedup lowest-to-highest thread lane with at least 1.000 ms of work; an outlier is over 8.0x its class median.

### A. Thread-flat on every host — 15 flagged (12 known)

| class | row | per-host (t_low, speedup) | note |
|:--|:--|:--|:--|
| reductions | co-spectrum vec.vec | Float32 64^3 | 12700K: 1.044 ms ×0.64 | **UNEXPLAINED** |
| reductions | co-spectrum vec.vec | Float64 64^3 | 12700K: 1.064 ms ×1.08 | **UNEXPLAINED** |
| reductions | cross-correlation vec.vec | Float32 64^3 | 12700K: 4.607 ms ×0.82; 9800X3D: 3.834 ms ×1.03 | known: the radial_correlation co-spectrum form — same materialization |
| reductions | radial_correlation vec | Float32 64^3 | 12700K: 4.219 ms ×0.74; 9800X3D: 3.505 ms ×0.97 | known: materializes its power field + inverse transform by design — decision 22 |
| reductions | radial_spectrum vec | Float32 128^3 | 12700K: 7.486 ms ×0.95; 9800X3D: 6.330 ms ×1.04 | **UNEXPLAINED** |
| reductions | reality_residual scalar | Float32 512^3 | 12700K: 7.867 ms ×0.97; 9800X3D: 2.783 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 256^3 | 12700K: 1.618 ms ×1.02; 9800X3D: 1.416 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 512^3 | 12700K: 13.108 ms ×1.03; 9800X3D: 5.798 ms ×0.99 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float32 256^3 | 12700K: 5.641 ms ×0.99; 9800X3D: 2.606 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float32 512^3 | 12700K: 34.370 ms ×1.01; 9800X3D: 16.162 ms ×0.94 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 128^3 | 12700K: 1.265 ms ×1.0; 9800X3D: 1.249 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 256^3 | 12700K: 8.667 ms ×0.91; 9800X3D: 5.034 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 512^3 | 12700K: 47.947 ms ×1.0; 9800X3D: 35.476 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | weighted_inner x3 separate | Float32 64^3 | 12700K: 1.056 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; BOTH hosts are now re-swept (2026-08-31) and the pathology is gone — the only surviving flags are the 64^3 rows, which carry ~1.1 ms of work against a 1 ms floor and are overhead-bound, not the pathology |
| reductions | weighted_inner x3 separate | Float64 64^3 | 12700K: 1.113 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; BOTH hosts are now re-swept (2026-08-31) and the pathology is gone — the only surviving flags are the 64^3 rows, which carry ~1.1 ms of work against a 1 ms floor and are overhead-bound, not the pathology |

### B. Declared-peer violations — 0 flagged (0 known)


## Shipped slower? — the history scan

Every cell's whole committed history, read at once — the drift and the step-in-an-unwatched-row that the canary, the triage and a one-archive-against-its-predecessor write-up all miss.

**A flagged cell is a hypothesis, not a regression.** This table mixes hosts, sweep shapes and measurement regimes, and documented effects move rows with no code change. Confirm with a matched A/B against the commit before the step before calling one real. The scan reads the *committed* history, so a sweep merged in this same change appears only at the next regeneration.

```
parsed 49 versions of RESULTS.md; 7461 (row, column) cells in-regime

=== cells at least 1.25x slower at HEAD than their in-regime best: 109

  2.77x  adapt plans (rebuild)              Float32 256^3    GPU 5070TI          0.023(08-17) ->     0.065  n=15  PERSISTENT
  2.21x  to_spectral vector                 Float32 512^3    GPU 7900XTX        20.298(08-07) ->    44.808  n=24  PERSISTENT
  1.91x  materialize_kernel separable       Float32 512^3    CPU 9800X3D t4     18.405(08-09) ->    35.141  n=28  PERSISTENT
  1.90x  materialize_kernel radial          Float32 512^3    CPU 9800X3D t4     16.917(08-09) ->    32.141  n=28  PERSISTENT
  1.87x  mean(norm) vec                     Float32 64^3     CPU 12700K t8       0.032(07-30) ->     0.060  n=28  one-off?
  1.74x  materialize_kernel separable       Float64 512^3    CPU 12700K t4      47.145(08-31) ->    81.939  n=24  one-off?
  1.72x  to_physical vector measure         Float64 128^3    CPU 12700K t2      18.363(08-07) ->    31.648  n=28  PERSISTENT
  1.72x  to_spectral vector measure         Float32 256^3    CPU 12700K t1     106.816(08-07) ->   183.803  n=28  PERSISTENT
  1.70x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t4    113.206(08-05) ->   192.895  n=28  PERSISTENT
  1.69x  materialize_kernel radial          Float64 512^3    CPU 12700K t4      45.526(08-31) ->    76.942  n=24  one-off?
  1.69x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t8     98.470(08-05) ->   166.208  n=28  PERSISTENT
  1.68x  to_spectral vector measure         Float64 128^3    CPU 12700K t2      15.038(07-30) ->    25.277  n=28  PERSISTENT
  1.67x  to_spectral scalar measure         Float32 512^3    CPU 12700K t2     224.043(08-07) ->   373.303  n=24  PERSISTENT
  1.66x  materialize_kernel separable       Float64 512^3    CPU 9800X3D t4     36.888(08-28) ->    61.319  n=28  one-off?
  1.62x  to_spectral vector measure         Float64 128^3    CPU 9800X3D t8      7.753(07-30) ->    12.576  n=28  one-off?
  1.62x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t1    290.357(07-30) ->   470.885  n=28  PERSISTENT
  1.62x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t2    165.853(08-09) ->   268.337  n=28  PERSISTENT
  1.61x  to_spectral scalar measure         Float64 256^3    CPU 9800X3D t2     36.865(08-09) ->    59.437  n=28  PERSISTENT
  1.61x  to_spectral vector measure         Float32 256^3    CPU 12700K t8      58.272(08-07) ->    93.801  n=28  one-off?
  1.61x  to_physical vector measure         Float32 256^3    CPU 12700K t1     125.496(08-07) ->   201.767  n=28  PERSISTENT
  1.59x  exponential_convolve! scalar       Float32 256^3    CPU 12700K t2      13.310(07-30) ->    21.149  n=28  one-off?
  1.56x  materialize_kernel radial          Float64 512^3    CPU 9800X3D t4     34.030(08-09) ->    53.247  n=28  one-off?
  1.56x  convolve! scalar                   Float32 64^3     CPU 12700K t2       0.026(08-07) ->     0.041  n=28  one-off?
  1.56x  to_physical vector                 Float64 128^3    CPU 12700K t2      19.672(08-07) ->    30.607  n=28  PERSISTENT
  1.56x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t2    188.250(07-30) ->   292.836  n=28  PERSISTENT
  1.55x  to_spectral vector measure         Float32 256^3    CPU 9800X3D t4     45.865(07-30) ->    71.275  n=28  PERSISTENT
  1.55x  to_spectral vector measure         Float64 128^3    CPU 9800X3D t2     12.032(08-09) ->    18.613  n=28  one-off?
  1.54x  to_spectral vector                 Float32 256^3    CPU 12700K t8      62.093(08-31) ->    95.495  n=28  one-off?
  1.54x  to_physical scalar measure         Float64 256^3    CPU 9800X3D t2     42.443(08-05) ->    65.252  n=28  PERSISTENT
  1.54x  to_physical vector                 Float32 512^3    GPU 7900XTX        36.129(08-07) ->    55.475  n=24  PERSISTENT
  1.53x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t4   3307.000(08-28) ->  5053.000  n=28  PERSISTENT
  1.52x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t4    145.316(07-30) ->   221.111  n=28  PERSISTENT
  1.51x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t1  12551.000(07-30) -> 18985.000  n=28  PERSISTENT
  1.51x  to_physical vector measure         Float64 128^3    CPU 9800X3D t2     12.492(08-09) ->    18.895  n=28  one-off?
  1.51x  to_physical scalar measure         Float32 512^3    CPU 12700K t2     274.759(08-07) ->   415.058  n=24  PERSISTENT
  1.51x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t8    131.139(08-10) ->   197.481  n=28  PERSISTENT
  1.49x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t2   6404.000(08-09) ->  9557.000  n=28  PERSISTENT
  1.49x  to_physical vector measure         Float32 256^3    CPU 12700K t8      74.747(08-07) ->   111.194  n=28  one-off?
  1.49x  convolve! scalar                   Float32 64^3     CPU 12700K t4       0.015(07-30) ->     0.022  n=28  one-off?
  1.48x  to_physical scalar                 Float64 256^3    CPU 9800X3D t2     49.727(08-05) ->    73.588  n=28  PERSISTENT
  1.47x  interpolate! CatmullRom            Float64 256^3    GPU 7900XTX         1.048(08-07) ->     1.545  n=24  PERSISTENT
  1.46x  exponential_convolve! scalar       Float32 256^3    CPU 12700K t4       7.294(07-30) ->    10.632  n=28  one-off?
  1.46x  interpolate! NUFFT                 Float64 256^3    GPU 7900XTX        40.571(08-07) ->    59.088  n=24  PERSISTENT
  1.45x  maximum scalar                     Float32 512^3    CPU 9800X3D t1     21.570(08-09) ->    31.382  n=28  one-off?
  1.44x  l2norm vec                         Float64 512^3    CPU 9800X3D t1     66.460(08-09) ->    95.940  n=28  PERSISTENT

=== operations flagged in 3+ columns (a code regression usually crosses columns):
   7 columns  to_physical vector measure
   6 columns  to_spectral vector measure
   5 columns  to_spectral scalar measure
   5 columns  to_physical scalar measure
   5 columns  interpolate! NUFFT
   4 columns  to_spectral vector
   4 columns  anterpolate! Lalescu(3,3)
   4 columns  divergence!∘kernel vec->scalar
   3 columns  materialize_kernel separable
   3 columns  materialize_kernel radial
   3 columns  exponential_convolve! scalar
   3 columns  to_physical vector
   3 columns  maximum scalar
   3 columns  helmholtz!∘kernel vec->vec
```
