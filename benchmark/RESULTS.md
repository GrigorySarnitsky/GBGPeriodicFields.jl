# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-08-24 at commit `dd893507` on Julia 1.12.6, assembled on host `Aiporetne` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–**512³** both element types) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). **Two columns for since-retired cards were DROPPED on 2026-08-07** — both were measured under the `gcsample` regime of PERFORMANCE.md §4(s), which inflated device rows 2–29×, and neither card is in the fleet to re-sweep, so those columns could never be corrected or compared against anything measured after the fix. Every remaining column is measured at the decision-38/39 rewrite. **Both GPU columns are now in the fixed measurement regime and are comparable again.** Device lanes used to run with a blanket `gcsample = true`, so a full `GC.gc()` — whose finalizers free device buffers and synchronize — preceded every sample and dominated operations lasting tens of microseconds, inflating device rows 18.4–29.2× at ``64^3``, 5.8–19.8× at ``128^3`` and 1.9–4.25× at ``256^3`` on the AMD card. `gcsample` is now decided per row from a measured device-pool probe and kept only for rows that genuinely materialize. **GPU 7900XTX was re-swept 2026-08-07** (median −81.6%) and **GPU 5070TI on 2026-08-09** (median −46.4% over 426 rows). The NVIDIA correction is the smaller of the two because that vendor's collect-and-synchronize is cheaper, not because less was wrong: the CUDA branch of the probe called `CUDA.available_memory`, which is not a binding, so it threw on every row and the catch-all held every CUDA row on the collector until 2026-08-09 — see PERFORMANCE.md §4(w), and note that a fallback reported as a measurement is the reason that went unnoticed. CPU columns were never affected, `gcsample` being gated on the backend. See PERFORMANCE.md §4(s). **`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and at the larger grids the shift does not reproduce:** across that host's 192 `fft` rows (four lanes × 48) against its 2026-07-22 archive, exactly **one** row at ``256^3`` moved slower and by +1.0%, where `Enteropia` moved +38%; per-lane medians run −4.5% to −6.8%. Twenty-three rows did move slower, but all except that one sit at ``64^3``/``128^3``, and the three exceeding 20% are small-grid high-thread-count cells where thread overhead dominates a sub-millisecond workload. This host's rows moved materially *faster* at the larger grids (up to a ratio of 0.54), which is no better explained, so a cross-vintage `fft` comparison is uninformative rather than evidence. `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. **The 2026-08-09 `Enteropia` re-sweep settles it: the shift was a ONE-OFF, not a persistent state change.** Re-measuring t1/t2/t4 against the 2026-08-05 archive over an interval with no source changes, the `fft` class is flat — per-lane medians −1.1% to −1.4%, and at ``256^3`` specifically −3.7%, −6.5% and −1.2%, where the event being explained was +20–50%. Every other class is flat too (600 rows per lane, overall medians +0.0%, −0.2%, −0.2%), so the sweep reproduces itself and the instrument is sound. Those three lanes are also the first archives carrying stamped platform state (kernel, microcode, governor, SMT, transparent huge pages), so a recurrence is now falsifiable instead of unattributable. See PERFORMANCE.md §4(p). **Five CPU rows are process-history-sensitive and comparable only against same-shaped sweeps — PERFORMANCE.md §4(y).** The two `materialize_kernel` rows, `lpnorm vec Inf`, `radial_correlation vec` and `cross-correlation vec.vec` measure faster at low thread counts inside a full sweep than standalone (up to ``3.2\times`` for `materialize_kernel` at ``t1``, ``1.2``–``1.7\times`` for the reductions three), because their per-call field-sized allocation lands in a regime selected by what streamed through the process before them; the eight allocating `fft` rows are verified clean. Every CPU column here is a full sweep, so the table is self-consistent, but those cells must not be compared against a standalone probe or a class-only lane, and `materialize_kernel` thread scaling should be read from ``t4`` upward (the ``t2`` cell of `materialize_kernel separable` is bistable across sweeps). **The `CPU 9800X3D t8` column was assembled from FOUR per-grid runs, not one lane.** A single `-t8` process segfaults on `Enteropia` inside FFTW's threaded executor — PERFORMANCE.md §4(q), reproducible there and never seen on the other host — and failed three times running. Splitting the lane by grid (`CHAR_SIZES=64`, then 128, 256, 512) completes it: 64³, 256³ and 512³ passed first time and 128³ on its second attempt, and the four part-archives merge into one lane archive with disjoint rows, 150 per grid. That is what an uncrashed process would have written, and it is a harness workaround rather than a fix — the fault is unchanged and a plain `characterize.jl` invocation at `-t8` will still die here. The merged column is flat against the 2026-08-05 one it replaces (median +0.0% over 600 rows), and its largest movers are the `measure` twins, whose FFTW `MEASURE` plan search legitimately re-decides between runs. A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field. Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `0f1caf57 @ 2026-08-09`: GPU 5070TI; `2d1f1de2 @ 2026-08-10`: CPU 9800X3D t8; `93d9d8da @ 2026-08-07`: GPU 7900XTX; `978a1609 @ 2026-08-09`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4; `bd1e4f30 @ 2026-08-07`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8. **Jitter is ~10% for most cells but NOT uniform: it reaches 1.44x at small grids under high thread counts.** Measured on the 12700K, `mean(norm) vec` `Float32`, five repeats of the same measurement: at ``64^3`` `-t8` the minimum came out 31.2, 31.0, 31.3, 30.8 and 44.4 us, where the same row at `-t1` spans 1.01x and at ``256^3`` `-t8` spans 1.09x. The work there (~31 us) is comparable to the cost of spawning eight threads, and taking BenchmarkTools' minimum over a one-second budget does not suppress it. So a movement of tens of percent in a small-grid, high-thread cell is NOT evidence of anything; compare those at ``256^3`` or above, or at low thread counts. PERFORMANCE.md §4(u).

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 3.940 ms | 2.704 ms | 2.251 ms | 2.117 ms | 2.732 ms | 1.473 ms | 824.541 μs | 520.655 μs | — | — |
| to_physical scalar measure | Float32 256^3 | 41.346 ms | 28.361 ms | 23.974 ms | 23.526 ms | 32.385 ms | 18.932 ms | 13.927 ms | 11.864 ms | — | — |
| to_physical scalar measure | Float32 512^3 | 520.095 ms | 274.759 ms | 231.175 ms | 274.469 ms | 374.989 ms | 195.892 ms | 146.662 ms | 131.139 ms | — | — |
| to_physical scalar measure | Float32 64^3 | 371.922 μs | 241.902 μs | 160.965 μs | 141.497 μs | 272.703 μs | 157.562 μs | 93.311 μs | 69.931 μs | — | — |
| to_physical scalar measure | Float64 128^3 | 6.068 ms | 5.522 ms | 5.182 ms | 4.508 ms | 4.040 ms | 2.237 ms | 1.551 ms | 1.719 ms | — | — |
| to_physical scalar measure | Float64 256^3 | 103.157 ms | 70.830 ms | 49.714 ms | 56.313 ms | 63.203 ms | 43.894 ms | 32.972 ms | 43.715 ms | — | — |
| to_physical scalar measure | Float64 512^3 | 1.102 s | 720.100 ms | 657.297 ms | 618.290 ms | 846.900 ms | 519.953 ms | 444.373 ms | 393.745 ms | — | — |
| to_physical scalar measure | Float64 64^3 | 545.365 μs | 351.124 μs | 260.592 μs | 226.641 μs | 360.204 μs | 205.323 μs | 129.021 μs | 98.281 μs | — | — |
| to_physical scalar | Float32 128^3 | 4.920 ms | 3.213 ms | 2.415 ms | 2.308 ms | 4.477 ms | 2.339 ms | 1.278 ms | 794.557 μs | 114.940 μs | 68.780 μs |
| to_physical scalar | Float32 256^3 | 88.021 ms | 49.841 ms | 33.533 ms | 26.385 ms | 167.282 ms | 88.930 ms | 48.040 ms | 27.416 ms | 1.114 ms | 1.113 ms |
| to_physical scalar | Float32 512^3 | 1.309 s | 667.091 ms | 506.857 ms | 390.054 ms | 2.032 s | 1.041 s | 555.714 ms | 323.836 ms | 13.304 ms | — |
| to_physical scalar | Float32 64^3 | 384.770 μs | 252.646 μs | 166.414 μs | 146.793 μs | 312.843 μs | 176.522 μs | 101.031 μs | 69.040 μs | 61.998 μs | 20.160 μs |
| to_physical scalar | Float64 128^3 | 7.749 ms | 5.805 ms | 4.775 ms | 4.337 ms | 9.722 ms | 5.482 ms | 2.986 ms | 1.859 ms | 308.747 μs | 433.482 μs |
| to_physical scalar | Float64 256^3 | 127.268 ms | 80.088 ms | 51.637 ms | 52.488 ms | 80.187 ms | 50.049 ms | 35.777 ms | 45.657 ms | 2.851 ms | 3.790 ms |
| to_physical scalar | Float64 512^3 | 1.450 s | 892.696 ms | 709.422 ms | 633.442 ms | 944.521 ms | 560.130 ms | 452.708 ms | 404.598 ms | — | — |
| to_physical scalar | Float64 64^3 | 672.104 μs | 404.924 μs | 286.897 μs | 276.351 μs | 531.796 μs | 290.403 μs | 166.542 μs | 114.531 μs | 87.954 μs | 52.800 μs |
| to_physical vector measure | Float32 128^3 | 11.689 ms | 8.998 ms | 8.221 ms | 7.647 ms | 9.102 ms | 5.813 ms | 3.759 ms | 3.012 ms | — | — |
| to_physical vector measure | Float32 256^3 | 125.496 ms | 94.289 ms | 75.629 ms | 74.747 ms | 127.707 ms | 78.565 ms | 54.348 ms | 62.446 ms | — | — |
| to_physical vector measure | Float32 512^3 | 1.861 s | 1.311 s | 1.015 s | 912.763 ms | 1.427 s | 953.820 ms | 687.081 ms | 618.253 ms | — | — |
| to_physical vector measure | Float32 64^3 | 1.231 ms | 809.758 μs | 564.304 μs | 498.312 μs | 861.859 μs | 502.695 μs | 291.303 μs | 197.992 μs | — | — |
| to_physical vector measure | Float64 128^3 | 30.774 ms | 18.363 ms | 21.288 ms | 27.609 ms | 22.043 ms | 12.492 ms | 13.363 ms | 13.488 ms | — | — |
| to_physical vector measure | Float64 256^3 | 361.550 ms | 268.443 ms | 234.660 ms | 227.607 ms | 308.583 ms | 187.406 ms | 168.784 ms | 157.118 ms | — | — |
| to_physical vector measure | Float64 512^3 | 3.338 s | 2.365 s | 2.031 s | 1.797 s | 2.516 s | 1.751 s | 1.351 s | 1.196 s | — | — |
| to_physical vector measure | Float64 64^3 | 1.988 ms | 1.748 ms | 1.271 ms | 1.358 ms | 1.114 ms | 684.357 μs | 407.234 μs | 317.423 μs | — | — |
| to_physical vector | Float32 128^3 | 14.719 ms | 11.254 ms | 7.979 ms | 7.291 ms | 14.361 ms | 10.166 ms | 5.398 ms | 3.725 ms | 349.248 μs | 249.441 μs |
| to_physical vector | Float32 256^3 | 263.761 ms | 187.728 ms | 116.684 ms | 97.607 ms | 523.133 ms | 359.743 ms | 187.727 ms | 161.609 ms | 5.600 ms | 3.499 ms |
| to_physical vector | Float32 512^3 | 4.218 s | 2.962 s | 1.764 s | 1.387 s | 6.290 s | 4.296 s | 2.304 s | 1.653 s | 36.129 ms | — |
| to_physical vector | Float32 64^3 | 1.273 ms | 984.725 μs | 561.725 μs | 481.941 μs | 988.379 μs | 679.517 μs | 318.333 μs | 209.213 μs | 71.413 μs | 39.050 μs |
| to_physical vector | Float64 128^3 | 35.147 ms | 19.672 ms | 25.810 ms | 25.688 ms | 40.070 ms | 25.055 ms | 18.981 ms | 16.781 ms | 960.784 μs | 1.408 ms |
| to_physical vector | Float64 256^3 | 435.564 ms | 343.093 ms | 242.970 ms | 228.550 ms | 354.803 ms | 229.184 ms | 172.038 ms | 154.850 ms | 12.478 ms | 11.355 ms |
| to_physical vector | Float64 512^3 | 4.538 s | 3.422 s | 2.259 s | 2.009 s | 2.810 s | 2.113 s | 1.405 s | 1.254 s | — | — |
| to_physical vector | Float64 64^3 | 2.542 ms | 2.131 ms | 1.398 ms | 1.193 ms | 1.627 ms | 1.103 ms | 566.835 μs | 403.014 μs | 143.480 μs | 131.651 μs |
| to_spectral scalar measure | Float32 128^3 | 3.332 ms | 2.325 ms | 1.567 ms | 1.196 ms | 2.749 ms | 1.432 ms | 778.440 μs | 465.625 μs | — | — |
| to_spectral scalar measure | Float32 256^3 | 35.032 ms | 22.432 ms | 19.125 ms | 18.101 ms | 32.733 ms | 19.484 ms | 12.939 ms | 9.930 ms | — | — |
| to_spectral scalar measure | Float32 512^3 | 488.544 ms | 224.043 ms | 271.721 ms | 267.653 ms | 382.683 ms | 165.853 ms | 117.079 ms | 101.492 ms | — | — |
| to_spectral scalar measure | Float32 64^3 | 362.043 μs | 202.388 μs | 136.870 μs | 98.325 μs | 272.382 μs | 149.431 μs | 84.530 μs | 56.331 μs | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.352 ms | 4.279 ms | 3.655 ms | 3.403 ms | 4.259 ms | 2.242 ms | 1.482 ms | 1.325 ms | — | — |
| to_spectral scalar measure | Float64 256^3 | 96.587 ms | 68.564 ms | 38.813 ms | 62.826 ms | 60.983 ms | 36.865 ms | 26.358 ms | 37.796 ms | — | — |
| to_spectral scalar measure | Float64 512^3 | 1.088 s | 631.184 ms | 567.274 ms | 527.390 ms | 759.730 ms | 448.250 ms | 379.671 ms | 330.013 ms | — | — |
| to_spectral scalar measure | Float64 64^3 | 498.914 μs | 294.077 μs | 194.581 μs | 228.182 μs | 342.304 μs | 189.212 μs | 112.041 μs | 80.281 μs | — | — |
| to_spectral scalar | Float32 128^3 | 4.355 ms | 2.699 ms | 1.747 ms | 1.679 ms | 4.354 ms | 2.278 ms | 1.204 ms | 722.277 μs | 77.694 μs | 40.870 μs |
| to_spectral scalar | Float32 256^3 | 84.124 ms | 45.903 ms | 29.063 ms | 21.624 ms | 165.948 ms | 86.493 ms | 45.665 ms | 26.418 ms | 651.168 μs | 684.480 μs |
| to_spectral scalar | Float32 512^3 | 1.289 s | 647.466 ms | 480.683 ms | 353.029 ms | 1.963 s | 981.179 ms | 518.016 ms | 289.159 ms | 9.570 ms | — |
| to_spectral scalar | Float32 64^3 | 363.076 μs | 209.386 μs | 130.953 μs | 105.406 μs | 301.333 μs | 165.921 μs | 91.541 μs | 58.751 μs | 51.190 μs | 14.850 μs |
| to_spectral scalar | Float64 128^3 | 6.933 ms | 5.128 ms | 3.945 ms | 3.368 ms | 10.269 ms | 5.538 ms | 2.929 ms | 1.943 ms | 257.021 μs | 399.032 μs |
| to_spectral scalar | Float64 256^3 | 140.834 ms | 87.104 ms | 46.038 ms | 64.462 ms | 172.410 ms | 89.794 ms | 53.139 ms | 51.745 ms | 2.430 ms | 3.057 ms |
| to_spectral scalar | Float64 512^3 | 1.577 s | 880.360 ms | 659.997 ms | 549.715 ms | 1.712 s | 896.211 ms | 596.670 ms | 430.708 ms | — | — |
| to_spectral scalar | Float64 64^3 | 631.171 μs | 355.908 μs | 222.473 μs | 195.482 μs | 497.535 μs | 273.653 μs | 153.622 μs | 95.711 μs | 77.482 μs | 45.681 μs |
| to_spectral vector measure | Float32 128^3 | 10.269 ms | 7.369 ms | 5.918 ms | 5.451 ms | 9.886 ms | 6.248 ms | 3.701 ms | 2.700 ms | — | — |
| to_spectral vector measure | Float32 256^3 | 106.816 ms | 72.627 ms | 59.081 ms | 58.272 ms | 119.990 ms | 70.955 ms | 46.651 ms | 62.787 ms | — | — |
| to_spectral vector measure | Float32 512^3 | 1.730 s | 1.170 s | 869.340 ms | 751.569 ms | 1.404 s | 888.612 ms | 629.799 ms | 518.049 ms | — | — |
| to_spectral vector measure | Float32 64^3 | 1.124 ms | 689.278 μs | 468.611 μs | 381.687 μs | 857.058 μs | 480.475 μs | 267.353 μs | 172.492 μs | — | — |
| to_spectral vector measure | Float64 128^3 | 27.195 ms | 15.470 ms | 22.360 ms | 12.680 ms | 22.772 ms | 12.032 ms | 12.640 ms | 12.833 ms | — | — |
| to_spectral vector measure | Float64 256^3 | 342.075 ms | 244.051 ms | 198.161 ms | 185.245 ms | 273.873 ms | 167.322 ms | 143.178 ms | 128.820 ms | — | — |
| to_spectral vector measure | Float64 512^3 | 3.271 s | 2.198 s | 1.720 s | 1.513 s | 2.238 s | 1.560 s | 1.120 s | 969.836 ms | — | — |
| to_spectral vector measure | Float64 64^3 | 1.791 ms | 1.443 ms | 985.889 μs | 718.537 μs | 1.064 ms | 629.246 μs | 386.494 μs | 251.953 μs | — | — |
| to_spectral vector | Float32 128^3 | 13.253 ms | 9.696 ms | 6.487 ms | 5.719 ms | 14.666 ms | 10.325 ms | 5.227 ms | 3.402 ms | 198.619 μs | 159.241 μs |
| to_spectral vector | Float32 256^3 | 257.120 ms | 178.171 ms | 99.371 ms | 80.132 ms | 512.088 ms | 349.744 ms | 178.275 ms | 149.431 ms | 3.517 ms | 2.254 ms |
| to_spectral vector | Float32 512^3 | 4.109 s | 2.923 s | 1.634 s | 1.256 s | 6.220 s | 4.260 s | 2.230 s | 1.569 s | 25.678 ms | — |
| to_spectral vector | Float32 64^3 | 1.205 ms | 875.734 μs | 475.570 μs | 395.918 μs | 945.610 μs | 650.717 μs | 290.493 μs | 180.672 μs | 60.315 μs | 22.800 μs |
| to_spectral vector | Float64 128^3 | 32.548 ms | 18.443 ms | 22.319 ms | 12.273 ms | 41.029 ms | 25.028 ms | 18.415 ms | 16.903 ms | 783.462 μs | 1.120 ms |
| to_spectral vector | Float64 256^3 | 488.801 ms | 367.693 ms | 232.568 ms | 204.396 ms | 624.835 ms | 401.211 ms | 248.810 ms | 194.734 ms | 11.643 ms | 9.185 ms |
| to_spectral vector | Float64 512^3 | 4.975 s | 3.661 s | 2.193 s | 1.837 s | 5.060 s | 3.631 s | 2.022 s | 1.583 s | — | — |
| to_spectral vector | Float64 64^3 | 2.079 ms | 1.860 ms | 1.176 ms | 806.065 μs | 1.568 ms | 1.066 ms | 529.435 μs | 341.244 μs | 126.340 μs | 112.460 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 388.209 μs | 236.369 μs | 170.421 μs | 74.913 μs | 161.782 μs | 83.961 μs | 44.810 μs | 37.151 μs | 60.557 μs | 34.661 μs |
| add! scalar | Float32 256^3 | 8.073 ms | 7.299 ms | 5.615 ms | 5.178 ms | 3.464 ms | 3.318 ms | 2.758 ms | 2.822 ms | 347.110 μs | 270.773 μs |
| add! scalar | Float32 512^3 | 68.673 ms | 62.603 ms | 48.877 ms | 45.609 ms | 40.458 ms | 36.710 ms | 36.784 ms | 37.230 ms | 2.556 ms | — |
| add! scalar | Float32 64^3 | 42.178 μs | 22.703 μs | 10.208 μs | 9.854 μs | 21.720 μs | 12.890 μs | 7.197 μs | 6.638 μs | 30.954 μs | 10.360 μs |
| add! scalar | Float64 128^3 | 1.461 ms | 1.286 ms | 958.019 μs | 807.698 μs | 324.284 μs | 164.911 μs | 86.461 μs | 74.471 μs | 61.219 μs | 37.180 μs |
| add! scalar | Float64 256^3 | 15.938 ms | 15.300 ms | 11.800 ms | 10.935 ms | 9.932 ms | 8.550 ms | 8.421 ms | 8.666 ms | 537.938 μs | 514.000 μs |
| add! scalar | Float64 512^3 | 136.659 ms | 126.580 ms | 97.743 ms | 91.293 ms | 80.625 ms | 73.555 ms | 73.485 ms | 74.113 ms | — | — |
| add! scalar | Float64 64^3 | 83.825 μs | 51.628 μs | 21.309 μs | 18.978 μs | 40.250 μs | 22.490 μs | 12.010 μs | 9.060 μs | 32.169 μs | 10.620 μs |
| combine! vec | Float32 128^3 | 2.597 ms | 2.332 ms | 1.819 ms | 1.600 ms | 623.236 μs | 309.581 μs | 163.442 μs | 116.481 μs | 190.915 μs | 131.894 μs |
| combine! vec | Float32 256^3 | 25.251 ms | 23.119 ms | 18.200 ms | 16.717 ms | 13.775 ms | 13.232 ms | 13.599 ms | 13.820 ms | 1.359 ms | 957.743 μs |
| combine! vec | Float32 512^3 | 207.335 ms | 185.538 ms | 148.923 ms | 138.000 ms | 110.822 ms | 104.524 ms | 109.568 ms | 111.770 ms | 11.362 ms | — |
| combine! vec | Float32 64^3 | 126.992 μs | 69.138 μs | 39.003 μs | 20.367 μs | 62.760 μs | 34.010 μs | 19.830 μs | 14.700 μs | 46.555 μs | 22.700 μs |
| combine! vec | Float64 128^3 | 5.894 ms | 5.405 ms | 4.131 ms | 3.742 ms | 2.244 ms | 1.847 ms | 1.610 ms | 1.517 ms | 236.950 μs | 193.781 μs |
| combine! vec | Float64 256^3 | 49.976 ms | 46.284 ms | 36.866 ms | 34.033 ms | 28.595 ms | 26.938 ms | 26.739 ms | 27.378 ms | 1.665 ms | 1.533 ms |
| combine! vec | Float64 512^3 | 407.338 ms | 375.527 ms | 293.122 ms | 275.044 ms | 226.215 ms | 209.303 ms | 220.306 ms | 220.709 ms | — | — |
| combine! vec | Float64 64^3 | 260.077 μs | 140.990 μs | 81.376 μs | 46.383 μs | 123.071 μs | 67.241 μs | 34.361 μs | 27.080 μs | 48.695 μs | 23.020 μs |
| cross! | Float32 128^3 | 2.931 ms | 2.398 ms | 2.118 ms | 1.967 ms | 1.957 ms | 994.155 μs | 493.056 μs | 249.482 μs | 51.046 μs | 84.202 μs |
| cross! | Float32 256^3 | 27.269 ms | 24.773 ms | 23.393 ms | 22.109 ms | 24.615 ms | 14.034 ms | 12.346 ms | 12.744 ms | 853.987 μs | 774.111 μs |
| cross! | Float32 512^3 | 227.705 ms | 202.770 ms | 192.348 ms | 183.951 ms | 152.778 ms | 110.320 ms | 110.255 ms | 112.278 ms | 7.355 ms | — |
| cross! | Float32 64^3 | 256.097 μs | 132.155 μs | 68.616 μs | 38.814 μs | 224.472 μs | 116.051 μs | 59.031 μs | 32.670 μs | 35.411 μs | 10.250 μs |
| cross! | Float64 128^3 | 6.250 ms | 5.759 ms | 5.075 ms | 4.877 ms | 3.845 ms | 2.233 ms | 1.642 ms | 1.489 ms | 231.569 μs | 197.230 μs |
| cross! | Float64 256^3 | 52.123 ms | 50.663 ms | 47.305 ms | 45.604 ms | 43.899 ms | 29.886 ms | 26.904 ms | 27.898 ms | 1.639 ms | 1.540 ms |
| cross! | Float64 512^3 | 412.992 ms | 409.844 ms | 382.736 ms | 369.731 ms | 303.741 ms | 215.266 ms | 220.828 ms | 223.543 ms | — | — |
| cross! | Float64 64^3 | 358.517 μs | 184.977 μs | 96.655 μs | 54.729 μs | 225.002 μs | 116.021 μs | 59.191 μs | 34.821 μs | 40.744 μs | 18.350 μs |
| det! tensor | Float32 128^3 | 3.328 ms | 2.464 ms | 2.006 ms | 1.795 ms | 2.196 ms | 1.087 ms | 548.927 μs | 292.343 μs | 74.568 μs | 102.783 μs |
| det! tensor | Float32 256^3 | 33.753 ms | 25.624 ms | 22.255 ms | 19.874 ms | 26.923 ms | 17.984 ms | 12.037 ms | 11.914 ms | 935.334 μs | 837.791 μs |
| det! tensor | Float32 512^3 | 246.816 ms | 196.652 ms | 180.822 ms | 165.881 ms | 210.622 ms | 116.650 ms | 103.996 ms | 102.884 ms | 7.869 ms | — |
| det! tensor | Float32 64^3 | 306.996 μs | 162.094 μs | 81.729 μs | 46.453 μs | 255.732 μs | 128.131 μs | 66.681 μs | 35.881 μs | 41.205 μs | 12.180 μs |
| det! tensor | Float64 128^3 | 6.405 ms | 5.546 ms | 4.775 ms | 4.289 ms | 3.995 ms | 1.950 ms | 1.650 ms | 1.623 ms | 249.941 μs | 197.531 μs |
| det! tensor | Float64 256^3 | 48.213 ms | 48.572 ms | 43.502 ms | 39.145 ms | 41.787 ms | 27.354 ms | 25.422 ms | 24.978 ms | 1.764 ms | 1.679 ms |
| det! tensor | Float64 512^3 | 374.082 ms | 400.702 ms | 340.725 ms | 309.426 ms | 359.454 ms | 240.317 ms | 206.961 ms | 207.730 ms | — | — |
| det! tensor | Float64 64^3 | 353.499 μs | 191.768 μs | 105.859 μs | 62.011 μs | 259.283 μs | 129.731 μs | 66.630 μs | 38.721 μs | 43.388 μs | 21.920 μs |
| dot! vec.vec | Float32 128^3 | 2.801 ms | 1.659 ms | 1.250 ms | 1.094 ms | 2.452 ms | 1.245 ms | 626.459 μs | 326.143 μs | 83.889 μs | 69.462 μs |
| dot! vec.vec | Float32 256^3 | 23.089 ms | 16.664 ms | 15.307 ms | 13.902 ms | 21.703 ms | 11.377 ms | 8.089 ms | 8.018 ms | 657.554 μs | 581.628 μs |
| dot! vec.vec | Float32 512^3 | 197.477 ms | 138.245 ms | 125.530 ms | 114.873 ms | 184.141 ms | 87.977 ms | 74.170 ms | 75.994 ms | 5.132 ms | — |
| dot! vec.vec | Float32 64^3 | 329.279 μs | 201.884 μs | 104.408 μs | 59.006 μs | 311.083 μs | 159.962 μs | 81.381 μs | 45.210 μs | 34.583 μs | 14.100 μs |
| dot! vec.vec | Float64 128^3 | 4.241 ms | 3.743 ms | 3.108 ms | 2.856 ms | 3.427 ms | 1.840 ms | 998.734 μs | 619.836 μs | 173.709 μs | 136.621 μs |
| dot! vec.vec | Float64 256^3 | 39.060 ms | 35.067 ms | 29.190 ms | 26.830 ms | 36.939 ms | 19.577 ms | 18.086 ms | 17.937 ms | 1.218 ms | 1.156 ms |
| dot! vec.vec | Float64 512^3 | 297.167 ms | 278.968 ms | 232.243 ms | 216.914 ms | 214.581 ms | 151.288 ms | 148.474 ms | 150.819 ms | — | — |
| dot! vec.vec | Float64 64^3 | 337.330 μs | 213.313 μs | 106.683 μs | 63.337 μs | 318.443 μs | 160.821 μs | 81.401 μs | 44.481 μs | 34.942 μs | 15.180 μs |
| map!(+) vec | Float32 128^3 | 2.918 ms | 2.404 ms | 2.077 ms | 1.970 ms | 1.745 ms | 839.324 μs | 413.795 μs | 210.632 μs | 51.024 μs | 72.583 μs |
| map!(+) vec | Float32 256^3 | 27.153 ms | 24.773 ms | 23.295 ms | 22.193 ms | 21.589 ms | 13.709 ms | 12.345 ms | 12.778 ms | 852.095 μs | 774.061 μs |
| map!(+) vec | Float32 512^3 | 224.921 ms | 202.036 ms | 192.171 ms | 183.733 ms | 135.151 ms | 109.684 ms | 109.944 ms | 111.887 ms | 6.801 ms | — |
| map!(+) vec | Float32 64^3 | 246.068 μs | 129.376 μs | 69.145 μs | 37.851 μs | 201.092 μs | 94.781 μs | 48.750 μs | 27.700 μs | 35.155 μs | 10.370 μs |
| map!(+) vec | Float64 128^3 | 6.207 ms | 5.662 ms | 5.053 ms | 4.902 ms | 3.750 ms | 2.232 ms | 1.609 ms | 1.503 ms | 232.656 μs | 197.911 μs |
| map!(+) vec | Float64 256^3 | 51.690 ms | 50.585 ms | 47.081 ms | 45.616 ms | 39.764 ms | 29.512 ms | 27.788 ms | 27.971 ms | 1.624 ms | 1.540 ms |
| map!(+) vec | Float64 512^3 | 408.672 ms | 409.233 ms | 381.435 ms | 368.940 ms | 293.875 ms | 214.551 ms | 220.371 ms | 223.284 ms | — | — |
| map!(+) vec | Float64 64^3 | 347.120 μs | 185.466 μs | 99.091 μs | 55.074 μs | 202.852 μs | 94.671 μs | 56.971 μs | 30.090 μs | 37.006 μs | 13.530 μs |
| map!(det) tensor | Float32 128^3 | 3.299 ms | 2.463 ms | 1.944 ms | 1.780 ms | 2.180 ms | 1.085 ms | 544.857 μs | 291.753 μs | 74.570 μs | 102.913 μs |
| map!(det) tensor | Float32 256^3 | 33.741 ms | 25.569 ms | 21.965 ms | 19.736 ms | 26.761 ms | 17.985 ms | 12.054 ms | 11.920 ms | 930.303 μs | 838.712 μs |
| map!(det) tensor | Float32 512^3 | 245.565 ms | 196.788 ms | 179.313 ms | 164.276 ms | 215.748 ms | 116.830 ms | 103.744 ms | 102.691 ms | 7.522 ms | — |
| map!(det) tensor | Float32 64^3 | 302.407 μs | 157.977 μs | 79.788 μs | 48.134 μs | 253.783 μs | 128.112 μs | 67.591 μs | 35.350 μs | 41.089 μs | 11.970 μs |
| map!(det) tensor | Float64 128^3 | 6.411 ms | 5.559 ms | 4.790 ms | 4.298 ms | 3.994 ms | 1.905 ms | 1.647 ms | 1.618 ms | 262.578 μs | 196.941 μs |
| map!(det) tensor | Float64 256^3 | 48.213 ms | 48.708 ms | 43.442 ms | 39.103 ms | 41.102 ms | 28.009 ms | 25.827 ms | 24.950 ms | 1.763 ms | 1.714 ms |
| map!(det) tensor | Float64 512^3 | 373.637 ms | 400.176 ms | 342.339 ms | 309.659 ms | 348.886 ms | 230.674 ms | 205.951 ms | 207.405 ms | — | — |
| map!(det) tensor | Float64 64^3 | 351.321 μs | 184.872 μs | 107.432 μs | 62.416 μs | 251.592 μs | 128.732 μs | 66.181 μs | 38.170 μs | 42.628 μs | 20.200 μs |
| mul! tensor.vec | Float32 128^3 | 5.085 ms | 4.259 ms | 3.736 ms | 3.545 ms | 3.523 ms | 1.943 ms | 974.692 μs | 765.507 μs | 213.240 μs | 150.344 μs |
| mul! tensor.vec | Float32 256^3 | 48.770 ms | 40.311 ms | 37.044 ms | 34.905 ms | 33.121 ms | 27.745 ms | 21.338 ms | 21.968 ms | 1.440 ms | 1.254 ms |
| mul! tensor.vec | Float32 512^3 | 403.678 ms | 313.946 ms | 302.395 ms | 285.772 ms | 336.936 ms | 200.994 ms | 176.403 ms | 174.528 ms | 11.929 ms | — |
| mul! tensor.vec | Float32 64^3 | 434.693 μs | 234.878 μs | 121.989 μs | 67.468 μs | 370.843 μs | 212.122 μs | 107.741 μs | 57.890 μs | 46.998 μs | 13.740 μs |
| mul! tensor.vec | Float64 128^3 | 10.698 ms | 9.242 ms | 9.156 ms | 8.672 ms | 7.030 ms | 4.831 ms | 4.427 ms | 4.275 ms | 390.915 μs | 320.821 μs |
| mul! tensor.vec | Float64 256^3 | 80.789 ms | 78.511 ms | 74.473 ms | 71.012 ms | 61.216 ms | 49.622 ms | 43.217 ms | 42.975 ms | 2.806 ms | 2.535 ms |
| mul! tensor.vec | Float64 512^3 | 606.952 ms | 632.000 ms | 592.094 ms | 565.883 ms | 549.255 ms | 379.984 ms | 346.513 ms | 344.961 ms | — | — |
| mul! tensor.vec | Float64 64^3 | 704.424 μs | 457.010 μs | 344.518 μs | 204.337 μs | 375.534 μs | 214.543 μs | 109.391 μs | 59.081 μs | 45.913 μs | 25.481 μs |
| norm! vec | Float32 128^3 | 805.111 μs | 580.083 μs | 465.693 μs | 339.052 μs | 216.242 μs | 116.350 μs | 64.431 μs | 52.681 μs | 66.827 μs | 40.141 μs |
| norm! vec | Float32 256^3 | 10.068 ms | 9.420 ms | 7.829 ms | 7.169 ms | 4.908 ms | 4.185 ms | 4.055 ms | 4.228 ms | 455.723 μs | 338.334 μs |
| norm! vec | Float32 512^3 | 82.552 ms | 80.164 ms | 66.460 ms | 62.401 ms | 49.132 ms | 45.045 ms | 45.938 ms | 46.706 ms | 3.354 ms | — |
| norm! vec | Float32 64^3 | 53.448 μs | 38.390 μs | 19.352 μs | 16.953 μs | 28.630 μs | 20.390 μs | 12.611 μs | 11.310 μs | 32.270 μs | 11.480 μs |
| norm! vec | Float64 128^3 | 2.096 ms | 1.912 ms | 1.478 ms | 1.341 ms | 478.335 μs | 247.302 μs | 126.892 μs | 102.891 μs | 132.647 μs | 91.910 μs |
| norm! vec | Float64 256^3 | 21.357 ms | 19.485 ms | 16.164 ms | 15.044 ms | 11.908 ms | 10.351 ms | 10.183 ms | 10.555 ms | 935.300 μs | 666.373 μs |
| norm! vec | Float64 512^3 | 165.424 ms | 159.487 ms | 133.072 ms | 124.108 ms | 96.231 ms | 90.598 ms | 91.679 ms | 93.710 ms | — | — |
| norm! vec | Float64 64^3 | 157.715 μs | 89.236 μs | 50.120 μs | 32.556 μs | 56.260 μs | 37.360 μs | 21.180 μs | 16.600 μs | 40.881 μs | 18.890 μs |
| tr! tensor | Float32 128^3 | 691.097 μs | 523.363 μs | 440.842 μs | 322.273 μs | 214.052 μs | 112.741 μs | 70.101 μs | 51.740 μs | 65.463 μs | 39.761 μs |
| tr! tensor | Float32 256^3 | 10.241 ms | 9.433 ms | 7.656 ms | 7.048 ms | 5.162 ms | 4.437 ms | 4.286 ms | 4.411 ms | 419.196 μs | 333.795 μs |
| tr! tensor | Float32 512^3 | 84.908 ms | 77.523 ms | 64.685 ms | 61.041 ms | 48.233 ms | 45.318 ms | 46.268 ms | 46.791 ms | 3.416 ms | — |
| tr! tensor | Float32 64^3 | 52.733 μs | 32.379 μs | 15.337 μs | 13.594 μs | 27.900 μs | 18.600 μs | 10.850 μs | 9.340 μs | 32.381 μs | 11.190 μs |
| tr! tensor | Float64 128^3 | 2.087 ms | 1.877 ms | 1.437 ms | 1.305 ms | 445.654 μs | 245.432 μs | 125.042 μs | 99.251 μs | 71.947 μs | 69.630 μs |
| tr! tensor | Float64 256^3 | 20.335 ms | 19.187 ms | 15.923 ms | 14.596 ms | 11.582 ms | 10.546 ms | 10.514 ms | 10.757 ms | 729.404 μs | 672.264 μs |
| tr! tensor | Float64 512^3 | 153.574 ms | 155.349 ms | 130.436 ms | 121.342 ms | 99.362 ms | 90.875 ms | 92.926 ms | 93.871 ms | — | — |
| tr! tensor | Float64 64^3 | 104.769 μs | 60.834 μs | 34.275 μs | 19.486 μs | 53.120 μs | 31.430 μs | 18.700 μs | 14.050 μs | 33.554 μs | 11.370 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.570 ms | 2.817 ms | 1.534 ms | 1.201 ms | 3.218 ms | 1.663 ms | 834.281 μs | 429.164 μs | 54.268 μs | 37.081 μs |
| curl! vec->vec | Float32 256^3 | 44.143 ms | 22.594 ms | 17.329 ms | 16.603 ms | 25.992 ms | 13.163 ms | 8.878 ms | 8.564 ms | 599.665 μs | 541.347 μs |
| curl! vec->vec | Float32 512^3 | 352.634 ms | 178.081 ms | 143.986 ms | 137.109 ms | 229.409 ms | 111.251 ms | 84.609 ms | 83.694 ms | 4.585 ms | — |
| curl! vec->vec | Float32 64^3 | 701.076 μs | 360.763 μs | 183.790 μs | 97.418 μs | 419.394 μs | 215.352 μs | 108.421 μs | 60.281 μs | 36.591 μs | 12.220 μs |
| curl! vec->vec | Float64 128^3 | 5.472 ms | 3.970 ms | 3.543 ms | 3.407 ms | 3.698 ms | 1.882 ms | 942.263 μs | 528.505 μs | 132.590 μs | 139.841 μs |
| curl! vec->vec | Float64 256^3 | 48.491 ms | 38.152 ms | 35.526 ms | 34.402 ms | 33.338 ms | 22.758 ms | 19.349 ms | 20.599 ms | 1.171 ms | 1.076 ms |
| curl! vec->vec | Float64 512^3 | 357.994 ms | 295.934 ms | 285.142 ms | 276.230 ms | 245.371 ms | 160.991 ms | 162.439 ms | 166.184 ms | — | — |
| curl! vec->vec | Float64 64^3 | 669.677 μs | 353.934 μs | 178.966 μs | 98.998 μs | 476.654 μs | 236.862 μs | 118.511 μs | 65.591 μs | 46.655 μs | 28.550 μs |
| divergence! vec->scalar | Float32 128^3 | 3.488 ms | 1.379 ms | 714.512 μs | 410.273 μs | 3.384 ms | 1.109 ms | 570.417 μs | 292.903 μs | 58.304 μs | 32.761 μs |
| divergence! vec->scalar | Float32 256^3 | 28.222 ms | 11.020 ms | 9.254 ms | 8.271 ms | 26.743 ms | 9.037 ms | 4.546 ms | 4.144 ms | 395.405 μs | 342.135 μs |
| divergence! vec->scalar | Float32 512^3 | 225.599 ms | 89.683 ms | 78.305 ms | 70.431 ms | 211.190 ms | 69.515 ms | 46.506 ms | 46.897 ms | 2.937 ms | — |
| divergence! vec->scalar | Float32 64^3 | 427.450 μs | 176.172 μs | 92.150 μs | 51.564 μs | 434.944 μs | 151.382 μs | 77.051 μs | 43.291 μs | 33.643 μs | 12.190 μs |
| divergence! vec->scalar | Float64 128^3 | 3.577 ms | 2.025 ms | 1.630 ms | 1.420 ms | 3.388 ms | 1.042 ms | 542.997 μs | 283.333 μs | 87.801 μs | 74.311 μs |
| divergence! vec->scalar | Float64 256^3 | 31.003 ms | 21.358 ms | 17.413 ms | 15.758 ms | 27.380 ms | 11.133 ms | 10.263 ms | 10.261 ms | 744.887 μs | 681.273 μs |
| divergence! vec->scalar | Float64 512^3 | 241.030 ms | 164.044 ms | 135.853 ms | 126.447 ms | 211.919 ms | 90.752 ms | 91.115 ms | 92.345 ms | — | — |
| divergence! vec->scalar | Float64 64^3 | 407.318 μs | 162.684 μs | 86.541 μs | 56.911 μs | 452.405 μs | 143.742 μs | 72.931 μs | 43.021 μs | 37.895 μs | 17.730 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 5.666 ms | 2.475 ms | 1.254 ms | 702.418 μs | 4.978 ms | 2.057 ms | 1.028 ms | 530.015 μs | 68.536 μs | 40.071 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 45.296 ms | 18.812 ms | 10.055 ms | 8.952 ms | 39.656 ms | 16.238 ms | 8.107 ms | 4.309 ms | 423.792 μs | 343.925 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | 358.585 ms | 148.701 ms | 84.490 ms | 75.767 ms | 312.006 ms | 127.090 ms | 64.531 ms | 46.939 ms | 3.431 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 704.011 μs | 323.268 μs | 163.944 μs | 90.991 μs | 636.496 μs | 269.602 μs | 137.851 μs | 74.491 μs | 36.052 μs | 14.290 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 5.773 ms | 2.442 ms | 1.726 ms | 1.441 ms | 4.936 ms | 1.995 ms | 983.843 μs | 509.145 μs | 107.119 μs | 92.490 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 47.041 ms | 22.120 ms | 17.989 ms | 16.251 ms | 39.402 ms | 15.812 ms | 10.331 ms | 10.279 ms | 755.065 μs | 676.143 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | 371.499 ms | 168.086 ms | 138.832 ms | 128.627 ms | 311.473 ms | 124.950 ms | 91.959 ms | 92.763 ms | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 697.877 μs | 309.333 μs | 158.013 μs | 89.429 μs | 638.356 μs | 259.183 μs | 130.891 μs | 73.361 μs | 42.687 μs | 22.230 μs |
| gradient! scalar->vec | Float32 128^3 | 3.126 ms | 1.674 ms | 877.614 μs | 514.574 μs | 1.967 ms | 978.104 μs | 492.856 μs | 253.343 μs | 45.579 μs | 28.501 μs |
| gradient! scalar->vec | Float32 256^3 | 25.011 ms | 14.353 ms | 13.055 ms | 12.729 ms | 15.585 ms | 7.825 ms | 5.712 ms | 5.663 ms | 441.593 μs | 379.445 μs |
| gradient! scalar->vec | Float32 512^3 | 199.337 ms | 116.955 ms | 111.158 ms | 107.159 ms | 125.170 ms | 66.503 ms | 63.251 ms | 64.294 ms | 3.415 ms | — |
| gradient! scalar->vec | Float32 64^3 | 392.515 μs | 215.930 μs | 106.683 μs | 58.804 μs | 247.452 μs | 126.341 μs | 64.620 μs | 34.950 μs | 34.365 μs | 11.220 μs |
| gradient! scalar->vec | Float64 128^3 | 3.352 ms | 2.822 ms | 2.461 ms | 2.283 ms | 2.061 ms | 988.270 μs | 502.036 μs | 256.293 μs | 96.900 μs | 93.861 μs |
| gradient! scalar->vec | Float64 256^3 | 30.957 ms | 28.470 ms | 27.121 ms | 26.391 ms | 20.364 ms | 14.764 ms | 14.054 ms | 14.112 ms | 903.515 μs | 748.144 μs |
| gradient! scalar->vec | Float64 512^3 | 234.597 ms | 227.254 ms | 221.627 ms | 215.372 ms | 153.629 ms | 127.654 ms | 126.617 ms | 128.299 ms | — | — |
| gradient! scalar->vec | Float64 64^3 | 361.664 μs | 189.697 μs | 97.431 μs | 59.724 μs | 261.443 μs | 125.052 μs | 64.011 μs | 36.581 μs | 41.009 μs | 20.060 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.366 ms | 2.237 ms | 1.410 ms | 1.200 ms | 3.384 ms | 1.697 ms | 853.881 μs | 437.465 μs | 56.797 μs | 37.752 μs |
| helmholtz! vec->vec | Float32 256^3 | 34.153 ms | 18.814 ms | 17.207 ms | 16.560 ms | 26.854 ms | 13.492 ms | 8.554 ms | 8.565 ms | 599.661 μs | 541.497 μs |
| helmholtz! vec->vec | Float32 512^3 | 272.421 ms | 152.183 ms | 144.369 ms | 137.372 ms | 231.177 ms | 115.442 ms | 82.365 ms | 83.784 ms | 4.617 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 550.289 μs | 284.226 μs | 145.361 μs | 78.711 μs | 451.394 μs | 226.853 μs | 113.531 μs | 62.441 μs | 37.002 μs | 12.760 μs |
| helmholtz! vec->vec | Float64 128^3 | 4.893 ms | 3.985 ms | 3.532 ms | 3.402 ms | 3.871 ms | 1.970 ms | 1.014 ms | 551.826 μs | 167.443 μs | 181.741 μs |
| helmholtz! vec->vec | Float64 256^3 | 45.002 ms | 38.172 ms | 35.478 ms | 34.248 ms | 35.105 ms | 20.386 ms | 21.576 ms | 19.548 ms | 1.194 ms | 1.334 ms |
| helmholtz! vec->vec | Float64 512^3 | 315.824 ms | 295.597 ms | 286.143 ms | 276.325 ms | 271.553 ms | 161.756 ms | 162.351 ms | 166.435 ms | — | — |
| helmholtz! vec->vec | Float64 64^3 | 582.096 μs | 305.179 μs | 154.864 μs | 89.158 μs | 523.565 μs | 264.502 μs | 133.871 μs | 72.731 μs | 53.199 μs | 34.040 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 7.476 ms | 3.848 ms | 1.972 ms | 1.257 ms | 6.322 ms | 3.161 ms | 1.593 ms | 814.048 μs | 65.590 μs | 42.121 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 59.239 ms | 30.726 ms | 17.653 ms | 16.575 ms | 50.181 ms | 25.110 ms | 12.597 ms | 8.539 ms | 592.501 μs | 541.987 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | 469.969 ms | 242.465 ms | 146.286 ms | 137.596 ms | 407.066 ms | 202.060 ms | 102.691 ms | 83.137 ms | 4.561 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 944.376 μs | 493.213 μs | 247.877 μs | 135.415 μs | 836.358 μs | 420.484 μs | 210.192 μs | 112.491 μs | 39.497 μs | 14.090 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 7.923 ms | 4.200 ms | 3.595 ms | 3.432 ms | 6.787 ms | 3.475 ms | 1.742 ms | 892.599 μs | 179.882 μs | 212.091 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 71.545 ms | 39.009 ms | 35.692 ms | 34.390 ms | 55.411 ms | 27.577 ms | 19.313 ms | 19.383 ms | 1.224 ms | 1.562 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | 512.004 ms | 297.228 ms | 286.499 ms | 276.579 ms | 452.591 ms | 227.831 ms | 163.665 ms | 165.387 ms | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 1.010 ms | 518.394 μs | 263.698 μs | 138.878 μs | 922.459 μs | 463.694 μs | 230.292 μs | 121.351 μs | 56.041 μs | 40.111 μs |
| inverse_laplacian! scalar | Float32 128^3 | 4.619 ms | 1.699 ms | 874.350 μs | 478.487 μs | 3.905 ms | 1.328 ms | 668.479 μs | 353.243 μs | 60.328 μs | 34.291 μs |
| inverse_laplacian! scalar | Float32 256^3 | 36.493 ms | 13.270 ms | 6.780 ms | 5.142 ms | 31.259 ms | 10.673 ms | 5.274 ms | 2.698 ms | 331.970 μs | 222.353 μs |
| inverse_laplacian! scalar | Float32 512^3 | 289.881 ms | 105.008 ms | 55.020 ms | 45.689 ms | 248.411 ms | 83.590 ms | 41.706 ms | 27.602 ms | 2.527 ms | — |
| inverse_laplacian! scalar | Float32 64^3 | 571.631 μs | 230.821 μs | 124.980 μs | 73.228 μs | 496.504 μs | 177.472 μs | 92.441 μs | 52.561 μs | 31.868 μs | 11.811 μs |
| inverse_laplacian! scalar | Float64 128^3 | 4.916 ms | 1.857 ms | 954.022 μs | 521.556 μs | 4.233 ms | 1.431 ms | 720.070 μs | 370.184 μs | 93.645 μs | 49.290 μs |
| inverse_laplacian! scalar | Float64 256^3 | 38.595 ms | 14.717 ms | 10.574 ms | 8.591 ms | 34.329 ms | 11.540 ms | 5.826 ms | 4.838 ms | 588.303 μs | 348.827 μs |
| inverse_laplacian! scalar | Float64 512^3 | 311.341 ms | 114.326 ms | 86.574 ms | 67.315 ms | 273.782 ms | 89.752 ms | 54.910 ms | 54.923 ms | — | — |
| inverse_laplacian! scalar | Float64 64^3 | 610.294 μs | 249.984 μs | 132.548 μs | 75.193 μs | 540.085 μs | 190.423 μs | 99.981 μs | 56.430 μs | 36.186 μs | 14.910 μs |
| laplacian! scalar | Float32 128^3 | 1.958 ms | 637.398 μs | 340.757 μs | 178.083 μs | 2.146 ms | 491.522 μs | 249.483 μs | 130.091 μs | 52.067 μs | 26.890 μs |
| laplacian! scalar | Float32 256^3 | 16.095 ms | 5.947 ms | 4.924 ms | 4.107 ms | 16.959 ms | 3.882 ms | 1.947 ms | 1.247 ms | 253.225 μs | 189.753 μs |
| laplacian! scalar | Float32 512^3 | 130.712 ms | 49.243 ms | 41.556 ms | 34.570 ms | 135.245 ms | 30.853 ms | 27.461 ms | 27.507 ms | 1.817 ms | — |
| laplacian! scalar | Float32 64^3 | 247.546 μs | 88.361 μs | 48.332 μs | 30.833 μs | 274.413 μs | 68.611 μs | 36.580 μs | 22.470 μs | 30.560 μs | 9.840 μs |
| laplacian! scalar | Float64 128^3 | 2.086 ms | 799.821 μs | 610.172 μs | 425.664 μs | 2.205 ms | 530.035 μs | 266.293 μs | 142.792 μs | 56.710 μs | 29.690 μs |
| laplacian! scalar | Float64 256^3 | 17.976 ms | 11.880 ms | 11.313 ms | 10.666 ms | 17.759 ms | 4.996 ms | 4.772 ms | 4.835 ms | 375.941 μs | 358.257 μs |
| laplacian! scalar | Float64 512^3 | 136.821 ms | 96.697 ms | 94.873 ms | 90.073 ms | 141.512 ms | 53.603 ms | 53.305 ms | 54.760 ms | — | — |
| laplacian! scalar | Float64 64^3 | 252.148 μs | 92.048 μs | 50.748 μs | 35.051 μs | 281.992 μs | 73.470 μs | 38.811 μs | 24.010 μs | 31.976 μs | 10.820 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 12.011 ms | 6.218 ms | 4.382 ms | 4.151 ms | 9.609 ms | 4.872 ms | 2.442 ms | 1.245 ms | 84.963 μs | 146.864 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 91.737 ms | 48.169 ms | 42.396 ms | 41.755 ms | 77.570 ms | 38.961 ms | 24.962 ms | 24.109 ms | 1.938 ms | 1.118 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | 719.902 ms | 388.330 ms | 348.213 ms | 336.925 ms | 654.982 ms | 320.305 ms | 209.027 ms | 199.866 ms | 14.724 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.439 ms | 735.446 μs | 376.005 μs | 199.969 μs | 1.215 ms | 617.397 μs | 310.143 μs | 161.652 μs | 44.229 μs | 18.230 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 13.391 ms | 10.959 ms | 9.649 ms | 9.488 ms | 10.354 ms | 5.376 ms | 3.773 ms | 3.757 ms | 454.036 μs | 289.171 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 115.709 ms | 91.065 ms | 86.479 ms | 84.782 ms | 92.681 ms | 53.860 ms | 48.880 ms | 49.220 ms | 3.517 ms | 2.223 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | 842.034 ms | 696.672 ms | 673.680 ms | 681.051 ms | 717.163 ms | 433.083 ms | 391.040 ms | 387.509 ms | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.535 ms | 791.321 μs | 413.076 μs | 221.171 μs | 1.277 ms | 647.727 μs | 325.543 μs | 167.451 μs | 55.551 μs | 42.210 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.184 μs | 1.116 μs | 1.122 μs | 1.118 μs | 1.181 μs | 1.166 μs | 1.172 μs | 1.168 μs | 78.810 μs | 28.151 μs |
| assignment_window | Float32 256^3 | 2.182 μs | 2.182 μs | 2.189 μs | 2.200 μs | 2.258 μs | 2.238 μs | 2.237 μs | 2.216 μs | 80.246 μs | 27.860 μs |
| assignment_window | Float32 512^3 | 4.430 μs | 4.419 μs | 4.440 μs | 4.459 μs | 4.549 μs | 4.476 μs | 4.460 μs | 4.459 μs | 74.877 μs | — |
| assignment_window | Float32 64^3 | 604.128 ns | 590.983 ns | 609.251 ns | 601.374 ns | 616.994 ns | 608.282 ns | 608.011 ns | 607.034 ns | 83.731 μs | 27.930 μs |
| assignment_window | Float64 128^3 | 1.466 μs | 1.505 μs | 1.496 μs | 1.577 μs | 1.556 μs | 1.565 μs | 1.557 μs | 1.569 μs | 75.875 μs | 29.330 μs |
| assignment_window | Float64 256^3 | 3.065 μs | 3.143 μs | 3.116 μs | 3.315 μs | 3.104 μs | 3.080 μs | 3.072 μs | 3.100 μs | 81.655 μs | 29.990 μs |
| assignment_window | Float64 512^3 | 5.945 μs | 6.063 μs | 6.048 μs | 6.401 μs | 5.974 μs | 5.946 μs | 5.960 μs | 5.954 μs | — | — |
| assignment_window | Float64 64^3 | 734.540 ns | 743.932 ns | 799.793 ns | 786.742 ns | 833.222 ns | 821.095 ns | 822.933 ns | 826.468 ns | 76.851 μs | 28.870 μs |
| combine!∘kernel vector | Float32 128^3 | 4.733 ms | 2.219 ms | 1.598 ms | 1.471 ms | 3.152 ms | 1.553 ms | 776.420 μs | 408.304 μs | 58.199 μs | 77.072 μs |
| combine!∘kernel vector | Float32 256^3 | 31.065 ms | 20.832 ms | 19.500 ms | 18.608 ms | 25.281 ms | 14.242 ms | 9.995 ms | 9.907 ms | 956.156 μs | 861.350 μs |
| combine!∘kernel vector | Float32 512^3 | 263.209 ms | 173.203 ms | 161.672 ms | 153.536 ms | 203.215 ms | 102.960 ms | 91.322 ms | 93.085 ms | 7.226 ms | — |
| combine!∘kernel vector | Float32 64^3 | 490.575 μs | 278.176 μs | 136.540 μs | 74.747 μs | 419.024 μs | 206.082 μs | 104.551 μs | 55.481 μs | 37.616 μs | 14.520 μs |
| combine!∘kernel vector | Float64 128^3 | 5.425 ms | 4.648 ms | 4.138 ms | 3.926 ms | 3.740 ms | 2.077 ms | 1.078 ms | 746.077 μs | 244.750 μs | 227.311 μs |
| combine!∘kernel vector | Float64 256^3 | 48.876 ms | 43.187 ms | 40.859 ms | 38.569 ms | 34.162 ms | 22.905 ms | 21.956 ms | 22.125 ms | 1.849 ms | 1.717 ms |
| combine!∘kernel vector | Float64 512^3 | 355.482 ms | 337.734 ms | 321.947 ms | 308.026 ms | 244.153 ms | 186.297 ms | 186.136 ms | 185.343 ms | — | — |
| combine!∘kernel vector | Float64 64^3 | 518.029 μs | 280.676 μs | 141.916 μs | 84.508 μs | 383.243 μs | 226.883 μs | 116.831 μs | 60.911 μs | 50.051 μs | 31.880 μs |
| convolve! scalar | Float32 128^3 | 1.593 ms | 299.555 μs | 202.038 μs | 87.165 μs | 922.239 μs | 102.811 μs | 54.191 μs | 39.251 μs | 42.054 μs | 21.801 μs |
| convolve! scalar | Float32 256^3 | 13.168 ms | 7.734 ms | 7.298 ms | 6.742 ms | 7.584 ms | 2.900 ms | 2.712 ms | 2.746 ms | 282.937 μs | 259.493 μs |
| convolve! scalar | Float32 512^3 | 105.047 ms | 65.771 ms | 63.420 ms | 59.295 ms | 62.108 ms | 37.052 ms | 36.521 ms | 37.139 ms | 2.061 ms | — |
| convolve! scalar | Float32 64^3 | 196.941 μs | 26.366 μs | 21.237 μs | 13.663 μs | 117.311 μs | 16.320 μs | 8.710 μs | 7.227 μs | 29.300 μs | 8.560 μs |
| convolve! scalar | Float64 128^3 | 1.766 ms | 1.342 ms | 1.158 ms | 1.024 ms | 1.006 ms | 172.722 μs | 93.441 μs | 72.531 μs | 57.277 μs | 35.680 μs |
| convolve! scalar | Float64 256^3 | 17.950 ms | 16.185 ms | 15.215 ms | 14.239 ms | 10.853 ms | 7.937 ms | 7.601 ms | 7.768 ms | 553.726 μs | 517.290 μs |
| convolve! scalar | Float64 512^3 | 144.010 ms | 132.439 ms | 125.743 ms | 118.467 ms | 89.752 ms | 74.762 ms | 73.720 ms | 74.130 ms | — | — |
| convolve! scalar | Float64 64^3 | 176.050 μs | 53.891 μs | 36.206 μs | 21.416 μs | 127.861 μs | 25.471 μs | 14.760 μs | 10.510 μs | 33.147 μs | 10.770 μs |
| convolve! vector | Float32 128^3 | 2.984 ms | 1.838 ms | 1.551 ms | 1.479 ms | 2.098 ms | 1.099 ms | 551.147 μs | 286.373 μs | 49.134 μs | 60.552 μs |
| convolve! vector | Float32 256^3 | 22.387 ms | 20.504 ms | 19.166 ms | 18.409 ms | 19.675 ms | 10.895 ms | 9.914 ms | 9.889 ms | 622.981 μs | 618.518 μs |
| convolve! vector | Float32 512^3 | 191.859 ms | 170.217 ms | 159.751 ms | 153.181 ms | 151.043 ms | 91.312 ms | 91.146 ms | 92.730 ms | 4.636 ms | — |
| convolve! vector | Float32 64^3 | 310.204 μs | 175.555 μs | 91.565 μs | 50.635 μs | 269.053 μs | 145.192 μs | 74.271 μs | 40.570 μs | 36.096 μs | 11.750 μs |
| convolve! vector | Float64 128^3 | 4.894 ms | 4.657 ms | 4.123 ms | 3.924 ms | 2.612 ms | 1.542 ms | 868.442 μs | 753.287 μs | 180.042 μs | 161.911 μs |
| convolve! vector | Float64 256^3 | 45.023 ms | 42.534 ms | 40.240 ms | 38.388 ms | 30.522 ms | 22.744 ms | 21.910 ms | 23.347 ms | 1.211 ms | 1.232 ms |
| convolve! vector | Float64 512^3 | 334.361 ms | 334.536 ms | 321.022 ms | 307.704 ms | 214.586 ms | 184.704 ms | 183.469 ms | 184.549 ms | — | — |
| convolve! vector | Float64 64^3 | 275.006 μs | 169.460 μs | 89.733 μs | 55.406 μs | 220.422 μs | 138.772 μs | 75.351 μs | 37.291 μs | 42.174 μs | 23.030 μs |
| convolve! vector ∘ radial    | Float32 128^3 | 4.137 ms | 2.168 ms | 1.467 ms | 1.230 ms | 2.498 ms | 1.250 ms | 619.778 μs | 319.083 μs | 125.566 μs | 83.212 μs |
| convolve! vector ∘ radial    | Float32 256^3 | 32.442 ms | 19.540 ms | 16.261 ms | 14.167 ms | 19.796 ms | 9.981 ms | 8.277 ms | 8.365 ms | 852.081 μs | 610.357 μs |
| convolve! vector ∘ radial    | Float32 512^3 | 260.754 ms | 153.051 ms | 125.871 ms | 105.766 ms | 160.345 ms | 81.768 ms | 81.274 ms | 93.492 ms | 6.554 ms | — |
| convolve! vector ∘ radial    | Float32 64^3 | 525.698 μs | 272.587 μs | 132.730 μs | 75.186 μs | 316.153 μs | 160.912 μs | 81.781 μs | 44.471 μs | 43.746 μs | 17.221 μs |
| convolve! vector ∘ radial    | Float64 128^3 | 5.089 ms | 4.032 ms | 3.543 ms | 2.914 ms | 2.878 ms | 1.458 ms | 726.269 μs | 412.764 μs | 163.756 μs | 136.801 μs |
| convolve! vector ∘ radial    | Float64 256^3 | 41.150 ms | 36.634 ms | 29.849 ms | 26.341 ms | 26.210 ms | 20.438 ms | 18.748 ms | 19.046 ms | 1.067 ms | 1.066 ms |
| convolve! vector ∘ radial    | Float64 512^3 | 328.914 ms | 292.288 ms | 227.544 ms | 198.790 ms | 194.606 ms | 159.754 ms | 162.605 ms | 163.974 ms | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | 532.804 μs | 275.934 μs | 146.401 μs | 94.811 μs | 351.373 μs | 176.712 μs | 91.631 μs | 48.421 μs | 46.419 μs | 18.950 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | 2.965 ms | 1.833 ms | 1.563 ms | 1.486 ms | 2.099 ms | 1.106 ms | 549.687 μs | 280.453 μs | 49.126 μs | 58.082 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | 22.549 ms | 20.741 ms | 19.339 ms | 18.401 ms | 19.707 ms | 10.927 ms | 9.885 ms | 9.878 ms | 620.835 μs | 618.797 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | 193.133 ms | 169.985 ms | 159.839 ms | 153.165 ms | 146.309 ms | 92.588 ms | 91.295 ms | 92.422 ms | 4.649 ms | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | 310.387 μs | 176.035 μs | 91.522 μs | 51.388 μs | 270.003 μs | 145.181 μs | 73.751 μs | 40.541 μs | 36.090 μs | 11.631 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | 4.923 ms | 4.608 ms | 4.180 ms | 3.932 ms | 2.615 ms | 1.532 ms | 867.192 μs | 750.087 μs | 180.471 μs | 162.001 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | 44.713 ms | 42.494 ms | 40.030 ms | 38.411 ms | 30.309 ms | 22.436 ms | 21.879 ms | 23.303 ms | 1.216 ms | 1.231 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | 333.016 ms | 334.888 ms | 320.659 ms | 307.456 ms | 211.443 ms | 183.174 ms | 183.241 ms | 183.957 ms | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | 276.289 μs | 168.856 μs | 88.106 μs | 52.225 μs | 220.733 μs | 137.892 μs | 75.461 μs | 37.681 μs | 42.120 μs | 22.860 μs |
| convolve! vector ∘ separable | Float32 128^3 | 6.760 ms | 3.455 ms | 1.754 ms | 1.213 ms | 4.666 ms | 2.346 ms | 1.169 ms | 591.166 μs | 130.674 μs | 84.622 μs |
| convolve! vector ∘ separable | Float32 256^3 | 53.473 ms | 27.624 ms | 17.239 ms | 13.202 ms | 37.269 ms | 18.658 ms | 9.395 ms | 8.450 ms | 867.930 μs | 616.487 μs |
| convolve! vector ∘ separable | Float32 512^3 | 426.551 ms | 218.832 ms | 136.861 ms | 106.705 ms | 294.913 ms | 148.262 ms | 81.528 ms | 82.742 ms | 6.851 ms | — |
| convolve! vector ∘ separable | Float32 64^3 | 842.577 μs | 435.665 μs | 225.713 μs | 118.591 μs | 588.766 μs | 298.043 μs | 150.473 μs | 77.831 μs | 43.832 μs | 17.450 μs |
| convolve! vector ∘ separable | Float64 128^3 | 6.753 ms | 4.128 ms | 3.389 ms | 2.475 ms | 3.952 ms | 1.990 ms | 997.644 μs | 510.675 μs | 241.880 μs | 208.571 μs |
| convolve! vector ∘ separable | Float64 256^3 | 53.841 ms | 36.812 ms | 29.162 ms | 23.952 ms | 32.745 ms | 19.455 ms | 18.965 ms | 19.233 ms | 1.696 ms | 1.594 ms |
| convolve! vector ∘ separable | Float64 512^3 | 428.037 ms | 295.548 ms | 232.862 ms | 189.892 ms | 259.680 ms | 156.383 ms | 163.323 ms | 164.761 ms | — | — |
| convolve! vector ∘ separable | Float64 64^3 | 808.651 μs | 436.674 μs | 215.832 μs | 120.351 μs | 494.325 μs | 249.453 μs | 126.451 μs | 66.711 μs | 57.607 μs | 34.431 μs |
| convolve! vector ∘ stored    | Float32 128^3 | 2.991 ms | 1.833 ms | 1.554 ms | 1.483 ms | 2.100 ms | 1.103 ms | 550.617 μs | 283.372 μs | 48.991 μs | 60.601 μs |
| convolve! vector ∘ stored    | Float32 256^3 | 22.564 ms | 20.516 ms | 19.219 ms | 18.417 ms | 19.714 ms | 10.946 ms | 9.952 ms | 9.905 ms | 621.345 μs | 618.058 μs |
| convolve! vector ∘ stored    | Float32 512^3 | 193.408 ms | 169.825 ms | 159.741 ms | 153.249 ms | 147.081 ms | 92.869 ms | 91.457 ms | 92.661 ms | 4.641 ms | — |
| convolve! vector ∘ stored    | Float32 64^3 | 309.962 μs | 178.565 μs | 91.368 μs | 54.553 μs | 270.223 μs | 145.102 μs | 74.491 μs | 40.201 μs | 36.063 μs | 11.700 μs |
| convolve! vector ∘ stored    | Float64 128^3 | 4.906 ms | 4.598 ms | 4.136 ms | 3.929 ms | 2.625 ms | 1.546 ms | 874.261 μs | 753.248 μs | 181.099 μs | 160.571 μs |
| convolve! vector ∘ stored    | Float64 256^3 | 44.753 ms | 42.666 ms | 40.028 ms | 38.471 ms | 30.548 ms | 22.757 ms | 21.924 ms | 22.075 ms | 1.214 ms | 1.229 ms |
| convolve! vector ∘ stored    | Float64 512^3 | 330.158 ms | 334.980 ms | 320.788 ms | 307.347 ms | 213.616 ms | 184.267 ms | 183.549 ms | 184.189 ms | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | 274.539 μs | 164.133 μs | 88.964 μs | 60.719 μs | 220.972 μs | 138.412 μs | 74.781 μs | 38.920 μs | 42.133 μs | 22.961 μs |
| exponential_convolve! scalar | Float32 128^3 | 6.109 ms | 2.702 ms | 1.361 ms | 722.348 μs | 5.044 ms | 2.118 ms | 1.065 ms | 542.335 μs | 50.382 μs | 26.981 μs |
| exponential_convolve! scalar | Float32 256^3 | 48.311 ms | 21.234 ms | 10.718 ms | 6.141 ms | 39.830 ms | 16.540 ms | 8.306 ms | 4.377 ms | 258.551 μs | 189.552 μs |
| exponential_convolve! scalar | Float32 512^3 | 384.722 ms | 167.829 ms | 84.785 ms | 50.497 ms | 317.337 ms | 131.750 ms | 67.951 ms | 34.887 ms | 1.888 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 762.967 μs | 349.962 μs | 179.859 μs | 101.305 μs | 641.867 μs | 280.853 μs | 144.643 μs | 78.210 μs | 31.027 μs | 9.900 μs |
| exponential_convolve! scalar | Float64 128^3 | 5.784 ms | 2.553 ms | 1.331 ms | 835.192 μs | 5.549 ms | 2.396 ms | 1.208 ms | 615.146 μs | 94.509 μs | 78.220 μs |
| exponential_convolve! scalar | Float64 256^3 | 45.717 ms | 20.058 ms | 12.133 ms | 10.752 ms | 43.859 ms | 18.831 ms | 9.499 ms | 4.997 ms | 600.686 μs | 565.660 μs |
| exponential_convolve! scalar | Float64 512^3 | 364.009 ms | 160.020 ms | 97.219 ms | 90.369 ms | 350.692 ms | 150.323 ms | 77.410 ms | 55.133 ms | — | — |
| exponential_convolve! scalar | Float64 64^3 | 719.321 μs | 328.503 μs | 170.993 μs | 103.498 μs | 698.116 μs | 313.573 μs | 158.511 μs | 85.951 μs | 39.895 μs | 18.030 μs |
| exponential_convolve! vector | Float32 128^3 | 20.248 ms | 9.678 ms | 4.892 ms | 2.629 ms | 16.579 ms | 7.694 ms | 3.848 ms | 1.950 ms | 131.385 μs | 86.193 μs |
| exponential_convolve! vector | Float32 256^3 | 160.278 ms | 76.157 ms | 38.541 ms | 22.375 ms | 130.858 ms | 60.311 ms | 31.218 ms | 15.565 ms | 866.298 μs | 628.098 μs |
| exponential_convolve! vector | Float32 512^3 | 1.274 s | 603.661 ms | 304.604 ms | 182.939 ms | 1.041 s | 481.001 ms | 241.359 ms | 125.574 ms | 6.877 ms | — |
| exponential_convolve! vector | Float32 64^3 | 2.542 ms | 1.233 ms | 639.809 μs | 332.578 μs | 2.128 ms | 996.140 μs | 503.627 μs | 261.002 μs | 43.958 μs | 17.660 μs |
| exponential_convolve! vector | Float64 128^3 | 19.539 ms | 9.328 ms | 4.822 ms | 3.554 ms | 18.764 ms | 8.647 ms | 4.354 ms | 2.205 ms | 263.200 μs | 219.411 μs |
| exponential_convolve! vector | Float64 256^3 | 154.206 ms | 72.909 ms | 38.108 ms | 33.695 ms | 148.158 ms | 68.008 ms | 35.112 ms | 19.341 ms | 1.887 ms | 1.671 ms |
| exponential_convolve! vector | Float64 512^3 | 1.226 s | 579.498 ms | 304.348 ms | 273.431 ms | 1.181 s | 542.706 ms | 272.155 ms | 165.636 ms | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.475 ms | 1.167 ms | 606.307 μs | 324.223 μs | 2.367 ms | 1.095 ms | 553.575 μs | 284.693 μs | 60.930 μs | 35.850 μs |
| inv separable | Float32 128^3 | 951.739 ns | 950.238 ns | 952.333 ns | 966.625 ns | 761.248 ns | 761.827 ns | 761.616 ns | 763.645 ns | 201.579 μs | 53.881 μs |
| inv separable | Float32 256^3 | 1.964 μs | 1.958 μs | 1.961 μs | 1.977 μs | 1.558 μs | 1.554 μs | 1.566 μs | 1.617 μs | 210.015 μs | 56.711 μs |
| inv separable | Float32 512^3 | 3.819 μs | 3.800 μs | 3.825 μs | 3.861 μs | 3.000 μs | 3.027 μs | 3.027 μs | 3.040 μs | 241.827 μs | — |
| inv separable | Float32 64^3 | 506.674 ns | 505.212 ns | 506.068 ns | 509.042 ns | 409.101 ns | 411.105 ns | 408.598 ns | 407.990 ns | 202.306 μs | 51.610 μs |
| inv separable | Float64 128^3 | 1.096 μs | 1.129 μs | 1.097 μs | 1.132 μs | 1.056 μs | 1.055 μs | 1.061 μs | 1.071 μs | 194.038 μs | 53.470 μs |
| inv separable | Float64 256^3 | 2.143 μs | 2.425 μs | 2.151 μs | 2.153 μs | 2.054 μs | 2.036 μs | 2.041 μs | 2.066 μs | 195.568 μs | 60.361 μs |
| inv separable | Float64 512^3 | 4.041 μs | 4.067 μs | 4.037 μs | 4.086 μs | 4.003 μs | 3.984 μs | 3.912 μs | 3.987 μs | — | — |
| inv separable | Float64 64^3 | 530.085 ns | 531.698 ns | 530.872 ns | 533.005 ns | 518.539 ns | 529.795 ns | 537.163 ns | 520.372 ns | 196.892 μs | 52.700 μs |
| materialize_kernel radial | Float32 128^3 | 1.380 ms | 607.802 μs | 408.922 μs | 232.532 μs | 1.131 ms | 351.851 μs | 179.052 μs | 93.401 μs | 55.598 μs | 26.751 μs |
| materialize_kernel radial | Float32 256^3 | 11.162 ms | 4.595 ms | 3.615 ms | 2.618 ms | 8.921 ms | 2.766 ms | 1.906 ms | 1.884 ms | 339.070 μs | 149.522 μs |
| materialize_kernel radial | Float32 512^3 | 88.854 ms | 36.249 ms | 28.671 ms | 21.990 ms | 70.877 ms | 22.102 ms | 16.917 ms | 17.154 ms | 4.562 ms | — |
| materialize_kernel radial | Float32 64^3 | 174.953 μs | 85.421 μs | 40.399 μs | 31.178 μs | 145.891 μs | 47.981 μs | 25.520 μs | 15.730 μs | 39.123 μs | 10.540 μs |
| materialize_kernel radial | Float64 128^3 | 1.481 ms | 916.003 μs | 693.147 μs | 440.954 μs | 1.176 ms | 376.404 μs | 259.003 μs | 325.063 μs | 64.210 μs | 30.300 μs |
| materialize_kernel radial | Float64 256^3 | 11.692 ms | 7.861 ms | 5.675 ms | 5.391 ms | 9.401 ms | 3.989 ms | 3.921 ms | 3.987 ms | 486.936 μs | 174.353 μs |
| materialize_kernel radial | Float64 512^3 | 93.204 ms | 142.965 ms | 76.707 ms | 47.893 ms | 74.816 ms | 33.938 ms | 34.030 ms | 35.693 ms | — | — |
| materialize_kernel radial | Float64 64^3 | 177.126 μs | 71.706 μs | 53.233 μs | 35.568 μs | 151.251 μs | 48.890 μs | 25.780 μs | 15.951 μs | 37.026 μs | 11.490 μs |
| materialize_kernel separable | Float32 128^3 | 1.794 ms | 782.748 μs | 448.019 μs | 322.260 μs | 1.534 ms | 446.533 μs | 225.793 μs | 117.181 μs | 56.445 μs | 26.511 μs |
| materialize_kernel separable | Float32 256^3 | 14.330 ms | 6.139 ms | 3.949 ms | 3.060 ms | 12.136 ms | 3.527 ms | 1.797 ms | 2.041 ms | 341.665 μs | 156.792 μs |
| materialize_kernel separable | Float32 512^3 | 114.889 ms | 49.178 ms | 31.341 ms | 23.919 ms | 96.532 ms | 28.113 ms | 18.405 ms | 17.817 ms | 4.659 ms | — |
| materialize_kernel separable | Float32 64^3 | 227.903 μs | 102.342 μs | 54.917 μs | 34.716 μs | 196.622 μs | 59.690 μs | 31.701 μs | 18.780 μs | 39.063 μs | 10.540 μs |
| materialize_kernel separable | Float64 128^3 | 1.778 ms | 958.451 μs | 773.722 μs | 503.520 μs | 1.451 ms | 463.685 μs | 271.743 μs | 306.793 μs | 86.700 μs | 50.440 μs |
| materialize_kernel separable | Float64 256^3 | 14.237 ms | 7.910 ms | 5.980 ms | 5.604 ms | 11.487 ms | 4.448 ms | 3.996 ms | 4.007 ms | 652.647 μs | 332.905 μs |
| materialize_kernel separable | Float64 512^3 | 114.959 ms | 63.370 ms | 82.029 ms | 50.289 ms | 91.639 ms | 38.299 ms | 58.586 ms | 43.805 ms | — | — |
| materialize_kernel separable | Float64 64^3 | 224.892 μs | 101.110 μs | 56.287 μs | 51.687 μs | 186.452 μs | 61.401 μs | 32.181 μs | 19.360 μs | 41.853 μs | 14.670 μs |
| radial_kernel | Float32 128^3 | 3.451 ns | 2.814 ns | 2.817 ns | 2.817 ns | 3.050 ns | 3.200 ns | 3.180 ns | 3.050 ns | 337.000 ns | 366.053 ns |
| radial_kernel | Float32 256^3 | 2.814 ns | 2.814 ns | 2.817 ns | 2.815 ns | 3.050 ns | 3.220 ns | 3.180 ns | 3.050 ns | 340.000 ns | 374.981 ns |
| radial_kernel | Float32 512^3 | 2.814 ns | 2.815 ns | 2.817 ns | 2.820 ns | 3.050 ns | 3.210 ns | 3.190 ns | 3.050 ns | 337.000 ns | — |
| radial_kernel | Float32 64^3 | 2.818 ns | 2.815 ns | 2.816 ns | 2.816 ns | 3.050 ns | 3.200 ns | 3.190 ns | 3.190 ns | 341.000 ns | 365.446 ns |
| radial_kernel | Float64 128^3 | 3.014 ns | 3.014 ns | 3.017 ns | 3.013 ns | 3.190 ns | 3.200 ns | 3.200 ns | 3.170 ns | 348.000 ns | 365.657 ns |
| radial_kernel | Float64 256^3 | 3.015 ns | 3.014 ns | 3.020 ns | 3.014 ns | 3.190 ns | 3.190 ns | 3.200 ns | 3.170 ns | 349.000 ns | 366.333 ns |
| radial_kernel | Float64 512^3 | 3.015 ns | 3.014 ns | 3.016 ns | 3.013 ns | 3.180 ns | 3.190 ns | 3.200 ns | 3.160 ns | — | — |
| radial_kernel | Float64 64^3 | 3.014 ns | 3.014 ns | 3.016 ns | 3.013 ns | 3.190 ns | 3.200 ns | 3.210 ns | 3.180 ns | 347.000 ns | 367.488 ns |
| spectral_band | Float32 128^3 | 12.428 ns | 10.398 ns | 11.325 ns | 11.830 ns | 9.399 ns | 9.379 ns | 9.228 ns | 8.799 ns | 357.000 ns | 371.568 ns |
| spectral_band | Float32 256^3 | 12.430 ns | 10.404 ns | 11.311 ns | 11.829 ns | 9.399 ns | 9.389 ns | 9.208 ns | 9.489 ns | 358.000 ns | 366.785 ns |
| spectral_band | Float32 512^3 | 12.417 ns | 10.391 ns | 11.282 ns | 11.829 ns | 9.389 ns | 9.389 ns | 9.229 ns | 9.419 ns | 341.000 ns | — |
| spectral_band | Float32 64^3 | 12.417 ns | 10.359 ns | 11.441 ns | 11.831 ns | 9.399 ns | 9.389 ns | 9.228 ns | 10.410 ns | 350.000 ns | 367.064 ns |
| spectral_band | Float64 128^3 | 11.688 ns | 10.924 ns | 11.498 ns | 11.851 ns | 10.881 ns | 10.290 ns | 9.329 ns | 9.820 ns | 349.000 ns | 371.845 ns |
| spectral_band | Float64 256^3 | 11.688 ns | 10.916 ns | 11.493 ns | 11.852 ns | 10.871 ns | 10.261 ns | 9.309 ns | 11.021 ns | 344.000 ns | 370.786 ns |
| spectral_band | Float64 512^3 | 11.668 ns | 10.915 ns | 11.499 ns | 11.855 ns | 10.882 ns | 10.280 ns | 9.329 ns | 10.411 ns | — | — |
| spectral_band | Float64 64^3 | 11.686 ns | 10.913 ns | 11.498 ns | 11.847 ns | 10.891 ns | 10.280 ns | 9.319 ns | 10.060 ns | 342.000 ns | 369.055 ns |
| spectral_cutoff | Float32 128^3 | 11.711 ns | 10.366 ns | 10.675 ns | 11.023 ns | 9.419 ns | 9.139 ns | 9.138 ns | 9.229 ns | 353.000 ns | 367.739 ns |
| spectral_cutoff | Float32 256^3 | 11.704 ns | 10.550 ns | 10.680 ns | 11.023 ns | 9.419 ns | 9.119 ns | 9.148 ns | 9.269 ns | 356.000 ns | 375.174 ns |
| spectral_cutoff | Float32 512^3 | 11.706 ns | 10.368 ns | 10.676 ns | 11.021 ns | 9.409 ns | 9.129 ns | 9.148 ns | 9.098 ns | 345.000 ns | — |
| spectral_cutoff | Float32 64^3 | 11.714 ns | 10.358 ns | 10.668 ns | 11.022 ns | 9.409 ns | 9.109 ns | 9.158 ns | 10.460 ns | 352.000 ns | 368.792 ns |
| spectral_cutoff | Float64 128^3 | 11.674 ns | 10.926 ns | 11.456 ns | 11.642 ns | 10.751 ns | 10.420 ns | 10.000 ns | 9.349 ns | 345.000 ns | 369.325 ns |
| spectral_cutoff | Float64 256^3 | 11.669 ns | 10.909 ns | 11.461 ns | 11.648 ns | 10.761 ns | 10.430 ns | 10.010 ns | 10.571 ns | 350.000 ns | 369.714 ns |
| spectral_cutoff | Float64 512^3 | 11.673 ns | 10.931 ns | 11.460 ns | 11.644 ns | 10.771 ns | 10.400 ns | 10.020 ns | 10.812 ns | — | — |
| spectral_cutoff | Float64 64^3 | 11.670 ns | 10.891 ns | 11.469 ns | 11.642 ns | 10.771 ns | 10.420 ns | 9.950 ns | 10.050 ns | 346.000 ns | 369.612 ns |
| translation_kernel | Float32 128^3 | 1.837 μs | 1.801 μs | 1.813 μs | 1.805 μs | 1.434 μs | 1.420 μs | 1.410 μs | 1.413 μs | 51.833 μs | 17.351 μs |
| translation_kernel | Float32 256^3 | 3.550 μs | 3.551 μs | 3.571 μs | 3.558 μs | 2.747 μs | 2.731 μs | 2.729 μs | 2.723 μs | 54.419 μs | 17.380 μs |
| translation_kernel | Float32 512^3 | 6.921 μs | 6.928 μs | 6.938 μs | 6.920 μs | 5.305 μs | 5.290 μs | 5.324 μs | 5.303 μs | 50.052 μs | — |
| translation_kernel | Float32 64^3 | 898.475 ns | 898.286 ns | 908.450 ns | 900.683 ns | 755.328 ns | 739.347 ns | 742.370 ns | 742.818 ns | 52.453 μs | 17.020 μs |
| translation_kernel | Float64 128^3 | 2.032 μs | 2.041 μs | 2.035 μs | 2.149 μs | 1.830 μs | 1.841 μs | 1.873 μs | 1.839 μs | 58.936 μs | 18.610 μs |
| translation_kernel | Float64 256^3 | 3.872 μs | 3.864 μs | 3.868 μs | 4.096 μs | 3.458 μs | 3.450 μs | 3.495 μs | 3.473 μs | 61.653 μs | 19.870 μs |
| translation_kernel | Float64 512^3 | 7.391 μs | 7.417 μs | 7.390 μs | 7.712 μs | 6.790 μs | 6.830 μs | 6.790 μs | 6.823 μs | — | — |
| translation_kernel | Float64 64^3 | 1.018 μs | 1.019 μs | 1.019 μs | 1.071 μs | 935.556 ns | 932.903 ns | 938.276 ns | 949.667 ns | 57.776 μs | 18.370 μs |
| translation_kernel! | Float32 128^3 | 1.775 μs | 1.757 μs | 1.775 μs | 1.761 μs | 1.375 μs | 1.367 μs | 1.368 μs | 1.368 μs | 31.682 μs | 14.191 μs |
| translation_kernel! | Float32 256^3 | 3.433 μs | 3.411 μs | 3.421 μs | 3.430 μs | 2.621 μs | 2.617 μs | 2.612 μs | 2.622 μs | 34.762 μs | 14.220 μs |
| translation_kernel! | Float32 512^3 | 6.790 μs | 6.763 μs | 6.760 μs | 6.778 μs | 5.127 μs | 5.115 μs | 5.122 μs | 5.123 μs | 31.335 μs | — |
| translation_kernel! | Float32 64^3 | 855.857 ns | 858.097 ns | 856.365 ns | 856.349 ns | 702.035 ns | 705.326 ns | 698.826 ns | 701.041 ns | 34.609 μs | 14.110 μs |
| translation_kernel! | Float64 128^3 | 1.869 μs | 1.861 μs | 1.869 μs | 1.896 μs | 1.686 μs | 1.691 μs | 1.716 μs | 1.699 μs | 36.474 μs | 15.510 μs |
| translation_kernel! | Float64 256^3 | 3.619 μs | 3.666 μs | 3.606 μs | 3.691 μs | 3.249 μs | 3.241 μs | 3.254 μs | 3.259 μs | 36.599 μs | 16.750 μs |
| translation_kernel! | Float64 512^3 | 7.133 μs | 7.091 μs | 7.125 μs | 7.262 μs | 6.376 μs | 6.360 μs | 6.328 μs | 6.358 μs | — | — |
| translation_kernel! | Float64 64^3 | 961.850 ns | 963.632 ns | 960.789 ns | 984.600 ns | 878.654 ns | 874.118 ns | 877.547 ns | 891.151 ns | 37.894 μs | 15.610 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.523 ms | 13.706 ms | 7.329 ms | 4.417 ms | 20.742 ms | 11.018 ms | 5.937 ms | 3.419 ms | 186.914 μs | 140.684 μs |
| anterpolate! CatmullRom | Float32 256^3 | 392.571 ms | 204.137 ms | 108.428 ms | 67.165 ms | 176.985 ms | 89.706 ms | 44.681 ms | 23.750 ms | 1.344 ms | 2.850 ms |
| anterpolate! CatmullRom | Float32 512^3 | 3.899 s | 2.043 s | 1.152 s | 802.658 ms | 2.956 s | 1.494 s | 779.705 ms | 431.109 ms | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.184 ms | 1.886 ms | 1.209 ms | 858.655 μs | 2.518 ms | 1.452 ms | 934.254 μs | 653.547 μs | 70.805 μs | 51.930 μs |
| anterpolate! CatmullRom | Float64 128^3 | 28.517 ms | 14.544 ms | 7.615 ms | 4.620 ms | 22.469 ms | 11.719 ms | 6.131 ms | 3.561 ms | 249.010 μs | 169.321 μs |
| anterpolate! CatmullRom | Float64 256^3 | 515.747 ms | 260.488 ms | 147.343 ms | 103.501 ms | 261.639 ms | 132.067 ms | 69.336 ms | 36.145 ms | 2.426 ms | 4.616 ms |
| anterpolate! CatmullRom | Float64 512^3 | 4.975 s | 2.629 s | 1.421 s | 881.899 ms | 3.279 s | 1.653 s | 899.223 ms | 532.488 ms | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.273 ms | 1.912 ms | 1.242 ms | 897.872 μs | 2.533 ms | 1.503 ms | 987.970 μs | 693.617 μs | 100.725 μs | 64.730 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 197.640 ms | 100.081 ms | 50.847 ms | 28.541 ms | 160.014 ms | 80.793 ms | 40.643 ms | 21.733 ms | 1.257 ms | 910.444 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.313 s | 1.165 s | 669.872 ms | 483.110 ms | 1.287 s | 657.162 ms | 321.767 ms | 162.216 ms | 14.164 ms | 14.934 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | 21.687 s | 11.570 s | 6.858 s | 5.090 s | 11.795 s | 6.020 s | 3.081 s | 1.627 s | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.886 ms | 13.323 ms | 8.134 ms | 5.592 ms | 19.880 ms | 10.638 ms | 6.447 ms | 4.341 ms | 401.373 μs | 260.621 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 203.551 ms | 105.091 ms | 52.715 ms | 29.850 ms | 160.698 ms | 80.783 ms | 40.559 ms | 21.654 ms | 1.995 ms | 1.090 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.781 s | 1.392 s | 837.619 ms | 617.127 ms | 1.397 s | 698.922 ms | 353.348 ms | 190.033 ms | 26.794 ms | 24.200 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | 23.251 s | 12.461 s | 7.362 s | 5.495 s | 12.657 s | 6.404 s | 3.350 s | 2.203 s | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.346 ms | 13.244 ms | 8.209 ms | 5.637 ms | 19.935 ms | 10.737 ms | 6.559 ms | 4.427 ms | 563.974 μs | 259.511 μs |
| anterpolate! NUFFT | Float32 128^3 | 396.778 ms | 226.554 ms | 136.043 ms | 108.198 ms | 357.647 ms | 191.398 ms | 99.333 ms | 59.788 ms | 2.950 ms | 2.796 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.215 s | 2.310 s | 1.384 s | 1.018 s | 3.754 s | 1.909 s | 1.037 s | 680.463 ms | 33.140 ms | 28.618 ms |
| anterpolate! NUFFT | Float32 512^3 | 38.579 s | 21.459 s | 12.714 s | 9.095 s | 30.890 s | 16.351 s | 9.040 s | 5.537 s | — | — |
| anterpolate! NUFFT | Float32 64^3 | 31.561 ms | 18.156 ms | 11.315 ms | 8.234 ms | 27.136 ms | 14.321 ms | 8.464 ms | 5.923 ms | 525.400 μs | 327.982 μs |
| anterpolate! NUFFT | Float64 128^3 | 515.978 ms | 298.422 ms | 216.821 ms | 176.299 ms | 418.711 ms | 230.303 ms | 144.742 ms | 100.381 ms | 10.092 ms | 6.539 ms |
| anterpolate! NUFFT | Float64 256^3 | 4.964 s | 2.890 s | 1.931 s | 1.565 s | 3.586 s | 2.004 s | 1.224 s | 874.590 ms | 55.413 ms | 58.464 ms |
| anterpolate! NUFFT | Float64 512^3 | 44.022 s | 25.243 s | 16.235 s | 12.790 s | 39.840 s | 21.729 s | 12.663 s | 8.264 s | — | — |
| anterpolate! NUFFT | Float64 64^3 | 36.987 ms | 21.460 ms | 14.337 ms | 10.866 ms | 33.390 ms | 17.777 ms | 10.756 ms | 7.131 ms | 951.238 μs | 712.594 μs |
| anterpolate! trilinear | Float32 128^3 | 4.695 ms | 2.261 ms | 1.352 ms | 881.126 μs | 4.568 ms | 2.524 ms | 1.407 ms | 859.638 μs | 52.056 μs | 28.911 μs |
| anterpolate! trilinear | Float32 256^3 | 80.940 ms | 44.334 ms | 25.586 ms | 20.086 ms | 43.373 ms | 22.274 ms | 11.212 ms | 6.554 ms | 308.344 μs | 684.988 μs |
| anterpolate! trilinear | Float32 512^3 | 730.809 ms | 400.257 ms | 248.098 ms | 201.541 ms | 749.572 ms | 381.702 ms | 212.602 ms | 117.736 ms | — | — |
| anterpolate! trilinear | Float32 64^3 | 485.517 μs | 322.905 μs | 208.906 μs | 161.045 μs | 370.194 μs | 248.803 μs | 165.942 μs | 127.541 μs | 34.865 μs | 15.240 μs |
| anterpolate! trilinear | Float64 128^3 | 5.140 ms | 2.667 ms | 1.561 ms | 1.087 ms | 5.990 ms | 3.278 ms | 1.864 ms | 1.185 ms | 66.586 μs | 49.711 μs |
| anterpolate! trilinear | Float64 256^3 | 93.226 ms | 51.331 ms | 33.258 ms | 27.126 ms | 71.163 ms | 36.641 ms | 20.170 ms | 11.407 ms | 637.033 μs | 1.059 ms |
| anterpolate! trilinear | Float64 512^3 | 788.544 ms | 452.004 ms | 270.764 ms | 210.306 ms | 768.945 ms | 393.645 ms | 218.274 ms | 129.702 ms | — | — |
| anterpolate! trilinear | Float64 64^3 | 522.769 μs | 338.908 μs | 241.823 μs | 191.637 μs | 379.164 μs | 262.013 μs | 176.891 μs | 135.091 μs | 46.714 μs | 24.030 μs |
| displace! 1-term | Float32 128^3 | 53.830 μs | 34.942 μs | 19.813 μs | 13.012 μs | — | — | — | — | 25.956 μs | — |
| displace! 1-term | Float32 256^3 | 466.209 μs | 263.686 μs | 135.063 μs | 73.291 μs | — | — | — | — | 40.262 μs | — |
| displace! 1-term | Float32 512^3 | 6.036 ms | 5.117 ms | 4.544 ms | 4.130 ms | — | — | — | — | — | — |
| displace! 1-term | Float32 64^3 | 6.737 μs | 7.199 μs | 5.428 μs | 5.967 μs | — | — | — | — | 25.791 μs | — |
| displace! 1-term | Float64 128^3 | 66.863 μs | 36.749 μs | 20.283 μs | 15.228 μs | — | — | — | — | 27.819 μs | — |
| displace! 1-term | Float64 256^3 | 948.336 μs | 557.894 μs | 427.815 μs | 216.328 μs | — | — | — | — | 45.661 μs | — |
| displace! 1-term | Float64 512^3 | 12.090 ms | 11.345 ms | 9.781 ms | 9.269 ms | — | — | — | — | — | — |
| displace! 1-term | Float64 64^3 | 7.078 μs | 7.319 μs | 5.575 μs | 6.599 μs | — | — | — | — | 26.785 μs | — |
| displace! 3-term torus | Float32 128^3 | 866.819 μs | 481.162 μs | 254.967 μs | 159.077 μs | — | — | — | — | 63.789 μs | — |
| displace! 3-term torus | Float32 256^3 | 7.065 ms | 3.756 ms | 1.969 ms | 1.142 ms | — | — | — | — | 58.564 μs | — |
| displace! 3-term torus | Float32 512^3 | 56.790 ms | 29.969 ms | 16.164 ms | 10.334 ms | — | — | — | — | — | — |
| displace! 3-term torus | Float32 64^3 | 107.941 μs | 108.082 μs | 107.937 μs | 105.779 μs | — | — | — | — | 50.365 μs | — |
| displace! 3-term torus | Float64 128^3 | 871.380 μs | 490.514 μs | 258.649 μs | 149.431 μs | — | — | — | — | 53.225 μs | — |
| displace! 3-term torus | Float64 256^3 | 7.025 ms | 3.790 ms | 2.000 ms | 1.410 ms | — | — | — | — | 91.502 μs | — |
| displace! 3-term torus | Float64 512^3 | 56.454 ms | 30.516 ms | 17.740 ms | 16.342 ms | — | — | — | — | — | — |
| displace! 3-term torus | Float64 64^3 | 108.280 μs | 108.158 μs | 108.382 μs | 106.021 μs | — | — | — | — | 65.335 μs | — |
| displace! 3-term | Float32 128^3 | 167.001 μs | 104.950 μs | 56.014 μs | 33.463 μs | — | — | — | — | 28.684 μs | — |
| displace! 3-term | Float32 256^3 | 1.470 ms | 850.045 μs | 470.063 μs | 239.996 μs | — | — | — | — | 45.439 μs | — |
| displace! 3-term | Float32 512^3 | 13.333 ms | 9.474 ms | 8.182 ms | 7.622 ms | — | — | — | — | — | — |
| displace! 3-term | Float32 64^3 | 20.896 μs | 17.857 μs | 11.928 μs | 10.046 μs | — | — | — | — | 25.650 μs | — |
| displace! 3-term | Float64 128^3 | 170.048 μs | 109.853 μs | 56.923 μs | 35.563 μs | — | — | — | — | 33.073 μs | — |
| displace! 3-term | Float64 256^3 | 2.185 ms | 1.698 ms | 1.435 ms | 1.235 ms | — | — | — | — | 64.565 μs | — |
| displace! 3-term | Float64 512^3 | 21.836 ms | 20.060 ms | 17.248 ms | 16.034 ms | — | — | — | — | — | — |
| displace! 3-term | Float64 64^3 | 20.901 μs | 18.513 μs | 11.953 μs | 10.347 μs | — | — | — | — | 29.115 μs | — |
| interpolate! CatmullRom | Float32 128^3 | 11.612 ms | 5.895 ms | 2.955 ms | 1.650 ms | 5.428 ms | 2.786 ms | 1.407 ms | 740.627 μs | 106.344 μs | 80.722 μs |
| interpolate! CatmullRom | Float32 256^3 | 271.654 ms | 139.395 ms | 75.000 ms | 47.020 ms | 59.365 ms | 29.394 ms | 13.167 ms | 7.124 ms | 627.839 μs | 803.859 μs |
| interpolate! CatmullRom | Float32 512^3 | 2.493 s | 1.307 s | 770.720 ms | 536.386 ms | 1.856 s | 920.235 ms | 482.228 ms | 258.785 ms | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.311 ms | 708.196 μs | 429.733 μs | 300.112 μs | 633.546 μs | 329.073 μs | 202.033 μs | 135.892 μs | 53.885 μs | 34.371 μs |
| interpolate! CatmullRom | Float64 128^3 | 12.345 ms | 6.808 ms | 3.482 ms | 1.941 ms | 5.627 ms | 2.937 ms | 1.458 ms | 772.507 μs | 136.993 μs | 132.050 μs |
| interpolate! CatmullRom | Float64 256^3 | 312.744 ms | 154.605 ms | 88.131 ms | 60.708 ms | 150.422 ms | 73.220 ms | 39.351 ms | 19.610 ms | 1.048 ms | 1.646 ms |
| interpolate! CatmullRom | Float64 512^3 | 2.726 s | 1.439 s | 765.411 ms | 487.613 ms | 1.962 s | 965.358 ms | 517.983 ms | 303.136 ms | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.360 ms | 739.388 μs | 449.929 μs | 314.905 μs | 670.417 μs | 354.534 μs | 215.472 μs | 144.631 μs | 80.880 μs | 63.871 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.947 ms | 37.408 ms | 18.912 ms | 10.471 ms | 42.333 ms | 21.416 ms | 10.699 ms | 5.669 ms | 559.598 μs | 409.621 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.512 s | 784.647 ms | 496.217 ms | 326.458 ms | 356.011 ms | 190.347 ms | 85.056 ms | 43.983 ms | 5.570 ms | 4.624 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | 15.272 s | 8.498 s | 5.646 s | 3.875 s | 5.372 s | 2.813 s | 1.493 s | 884.715 ms | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.741 ms | 4.700 ms | 2.857 ms | 1.950 ms | 5.084 ms | 2.681 ms | 1.603 ms | 1.082 ms | 306.223 μs | 215.131 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 78.951 ms | 42.466 ms | 21.810 ms | 12.118 ms | 41.629 ms | 20.980 ms | 10.501 ms | 5.546 ms | 824.893 μs | 772.043 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.986 s | 993.830 ms | 653.060 ms | 434.240 ms | 577.057 ms | 295.707 ms | 146.908 ms | 76.019 ms | 5.306 ms | 9.985 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | 16.377 s | 8.856 s | 5.559 s | 3.792 s | 6.413 s | 3.459 s | 1.813 s | 1.257 s | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.954 ms | 4.856 ms | 2.961 ms | 2.003 ms | 5.282 ms | 2.804 ms | 1.677 ms | 1.120 ms | 468.356 μs | 267.741 μs |
| interpolate! NUFFT | Float32 128^3 | 307.002 ms | 186.337 ms | 125.670 ms | 97.362 ms | 242.806 ms | 134.777 ms | 76.022 ms | 45.829 ms | 2.090 ms | 1.803 ms |
| interpolate! NUFFT | Float32 256^3 | 3.498 s | 1.980 s | 1.276 s | 917.061 ms | 2.967 s | 1.531 s | 858.915 ms | 607.798 ms | 26.237 ms | 17.655 ms |
| interpolate! NUFFT | Float32 512^3 | 31.922 s | 18.012 s | 11.453 s | 8.282 s | 24.704 s | 13.142 s | 7.671 s | 4.970 s | — | — |
| interpolate! NUFFT | Float32 64^3 | 16.519 ms | 10.207 ms | 6.795 ms | 5.326 ms | 12.215 ms | 6.498 ms | 3.819 ms | 2.534 ms | 413.539 μs | 298.952 μs |
| interpolate! NUFFT | Float64 128^3 | 421.433 ms | 255.981 ms | 192.904 ms | 161.776 ms | 223.198 ms | 134.504 ms | 96.663 ms | 77.522 ms | 8.509 ms | 5.508 ms |
| interpolate! NUFFT | Float64 256^3 | 3.901 s | 2.356 s | 1.699 s | 1.365 s | 1.969 s | 1.198 s | 854.414 ms | 718.001 ms | 40.571 ms | 47.795 ms |
| interpolate! NUFFT | Float64 512^3 | 35.462 s | 20.845 s | 14.870 s | 13.148 s | 24.912 s | 14.158 s | 9.166 s | 9.478 s | — | — |
| interpolate! NUFFT | Float64 64^3 | 21.974 ms | 14.169 ms | 10.812 ms | 9.007 ms | 17.867 ms | 9.981 ms | 5.956 ms | 4.009 ms | 835.506 μs | 844.885 μs |
| interpolate! trilinear | Float32 128^3 | 2.029 ms | 1.026 ms | 520.481 μs | 291.684 μs | 1.309 ms | 681.704 μs | 339.234 μs | 180.222 μs | 32.797 μs | 22.531 μs |
| interpolate! trilinear | Float32 256^3 | 54.025 ms | 28.417 ms | 15.244 ms | 8.952 ms | 15.123 ms | 7.971 ms | 3.236 ms | 1.775 ms | 120.643 μs | 184.972 μs |
| interpolate! trilinear | Float32 512^3 | 482.975 ms | 257.090 ms | 148.905 ms | 97.158 ms | 436.764 ms | 220.397 ms | 123.783 ms | 62.477 ms | — | — |
| interpolate! trilinear | Float32 64^3 | 227.223 μs | 124.212 μs | 77.823 μs | 55.854 μs | 147.632 μs | 79.011 μs | 48.080 μs | 33.140 μs | 30.081 μs | 12.850 μs |
| interpolate! trilinear | Float64 128^3 | 2.207 ms | 1.220 ms | 654.707 μs | 379.324 μs | 1.358 ms | 712.638 μs | 353.545 μs | 189.811 μs | 50.404 μs | 37.360 μs |
| interpolate! trilinear | Float64 256^3 | 60.265 ms | 31.979 ms | 19.700 ms | 13.551 ms | 32.519 ms | 16.644 ms | 7.992 ms | 4.353 ms | 238.024 μs | 348.426 μs |
| interpolate! trilinear | Float64 512^3 | 511.520 ms | 279.357 ms | 155.258 ms | 105.064 ms | 436.420 ms | 233.795 ms | 121.114 ms | 68.471 ms | — | — |
| interpolate! trilinear | Float64 64^3 | 239.320 μs | 132.276 μs | 81.600 μs | 57.898 μs | 162.212 μs | 87.841 μs | 49.670 μs | 33.610 μs | 40.168 μs | 21.130 μs |
| wrap! | Float32 128^3 | 526.428 μs | 337.965 μs | 168.903 μs | 114.155 μs | — | — | — | — | 35.636 μs | — |
| wrap! | Float32 256^3 | 4.257 ms | 2.623 ms | 1.303 ms | 848.706 μs | — | — | — | — | 43.670 μs | — |
| wrap! | Float32 512^3 | 34.015 ms | 20.658 ms | 10.568 ms | 7.612 ms | — | — | — | — | — | — |
| wrap! | Float32 64^3 | 65.705 μs | 65.589 μs | 65.615 μs | 64.332 μs | — | — | — | — | 34.478 μs | — |
| wrap! | Float64 128^3 | 576.324 μs | 370.903 μs | 194.994 μs | 125.910 μs | — | — | — | — | 39.668 μs | — |
| wrap! | Float64 256^3 | 4.660 ms | 2.957 ms | 1.508 ms | 887.407 μs | — | — | — | — | 52.011 μs | — |
| wrap! | Float64 512^3 | 37.471 ms | 23.418 ms | 11.922 ms | 7.668 ms | — | — | — | — | — | — |
| wrap! | Float64 64^3 | 71.689 μs | 71.537 μs | 71.838 μs | 70.138 μs | — | — | — | — | 35.852 μs | — |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.085 ms | 6.996 ms | 8.357 ms | 7.972 ms | 6.966 ms | 5.091 ms | 5.854 ms | 6.050 ms | 296.995 μs | 176.214 μs |
| co-spectrum vec.vec | Float32 256^3 | 64.252 ms | 47.546 ms | 45.730 ms | 42.525 ms | 55.226 ms | 37.112 ms | 31.828 ms | 29.987 ms | 966.187 μs | 838.340 μs |
| co-spectrum vec.vec | Float32 512^3 | 510.689 ms | 356.734 ms | 266.038 ms | 229.071 ms | 449.478 ms | 273.174 ms | 189.273 ms | 153.087 ms | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.044 ms | 1.386 ms | 1.531 ms | 1.605 ms | 905.269 μs | 968.440 μs | 1.226 ms | 1.321 ms | 221.511 μs | 72.040 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.408 ms | 6.415 ms | 5.999 ms | 5.322 ms | 7.266 ms | 5.271 ms | 4.555 ms | 4.464 ms | 17.366 ms | 257.721 μs |
| co-spectrum vec.vec | Float64 256^3 | 67.386 ms | 48.673 ms | 36.466 ms | 31.465 ms | 58.905 ms | 37.418 ms | 27.310 ms | 24.022 ms | 56.569 ms | 1.163 ms |
| co-spectrum vec.vec | Float64 512^3 | 556.430 ms | 370.769 ms | 239.490 ms | 195.985 ms | 474.969 ms | 300.750 ms | 181.636 ms | 130.125 ms | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.062 ms | 792.529 μs | 975.719 μs | 996.385 μs | 938.669 μs | 767.278 μs | 851.429 μs | 929.569 μs | 7.115 ms | 79.130 μs |
| cov vector | Float32 128^3 | 2.186 ms | 1.196 ms | 635.824 μs | 349.018 μs | 1.134 ms | 577.703 μs | 305.684 μs | 173.321 μs | 581.866 μs | 144.834 μs |
| cov vector | Float32 256^3 | 20.981 ms | 13.773 ms | 11.064 ms | 10.073 ms | 13.428 ms | 7.245 ms | 5.221 ms | 4.826 ms | 2.722 ms | 829.699 μs |
| cov vector | Float32 512^3 | 170.198 ms | 115.954 ms | 94.519 ms | 88.892 ms | 92.804 ms | 64.494 ms | 55.660 ms | 55.546 ms | — | — |
| cov vector | Float32 64^3 | 252.111 μs | 140.531 μs | 78.922 μs | 61.631 μs | 141.921 μs | 79.201 μs | 45.901 μs | 35.300 μs | 305.309 μs | 84.861 μs |
| cov vector | Float64 128^3 | 3.974 ms | 2.651 ms | 2.119 ms | 1.722 ms | 2.219 ms | 1.112 ms | 569.617 μs | 315.493 μs | 837.775 μs | 234.571 μs |
| cov vector | Float64 256^3 | 34.336 ms | 26.329 ms | 22.854 ms | 21.660 ms | 23.261 ms | 14.789 ms | 12.473 ms | 12.577 ms | 4.665 ms | 1.397 ms |
| cov vector | Float64 512^3 | 274.468 ms | 212.966 ms | 190.661 ms | 179.491 ms | 177.980 ms | 126.898 ms | 109.703 ms | 111.073 ms | — | — |
| cov vector | Float64 64^3 | 352.395 μs | 191.454 μs | 106.185 μs | 75.328 μs | 273.073 μs | 147.652 μs | 80.981 μs | 52.571 μs | 364.179 μs | 102.590 μs |
| cross-correlation vec.vec | Float32 128^3 | 37.668 ms | 33.117 ms | 33.833 ms | 33.859 ms | 32.920 ms | 24.624 ms | 21.849 ms | 21.129 ms | 755.001 μs | 572.973 μs |
| cross-correlation vec.vec | Float32 256^3 | 410.005 ms | 309.678 ms | 266.738 ms | 252.627 ms | 406.177 ms | 214.799 ms | 193.867 ms | 177.262 ms | 10.565 ms | 6.830 ms |
| cross-correlation vec.vec | Float32 512^3 | 3.812 s | 2.621 s | 1.856 s | 1.636 s | 2.934 s | 1.911 s | 1.400 s | 1.146 s | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.645 ms | 5.312 ms | 5.499 ms | 5.723 ms | 3.884 ms | 3.601 ms | 3.794 ms | 3.559 ms | 205.515 μs | 149.561 μs |
| cross-correlation vec.vec | Float64 128^3 | 57.857 ms | 55.261 ms | 41.756 ms | 49.781 ms | 43.149 ms | 30.477 ms | 32.063 ms | 31.005 ms | 36.448 ms | 2.017 ms |
| cross-correlation vec.vec | Float64 256^3 | 581.596 ms | 456.868 ms | 371.550 ms | 351.100 ms | 578.056 ms | 363.176 ms | 249.630 ms | 219.825 ms | 133.169 ms | 15.029 ms |
| cross-correlation vec.vec | Float64 512^3 | 5.734 s | 3.790 s | 2.943 s | 2.533 s | 4.556 s | 2.963 s | 2.069 s | 1.803 s | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.685 ms | 5.331 ms | 5.601 ms | 5.462 ms | 4.216 ms | 3.442 ms | 3.333 ms | 3.028 ms | 12.942 ms | 247.301 μs |
| inner spectral | Float32 128^3 | 2.464 ms | 1.649 ms | 1.380 ms | 1.229 ms | 1.426 ms | 814.465 μs | 503.607 μs | 358.343 μs | 200.948 μs | 122.343 μs |
| inner spectral | Float32 256^3 | 21.204 ms | 16.705 ms | 14.751 ms | 13.651 ms | 12.986 ms | 8.049 ms | 7.137 ms | 7.112 ms | 708.328 μs | 628.077 μs |
| inner spectral | Float32 512^3 | 164.737 ms | 128.807 ms | 112.670 ms | 106.006 ms | 102.670 ms | 79.036 ms | 68.389 ms | 69.744 ms | — | — |
| inner spectral | Float32 64^3 | 305.237 μs | 196.626 μs | 138.790 μs | 113.332 μs | 209.602 μs | 126.431 μs | 82.561 μs | 74.471 μs | 188.383 μs | 73.340 μs |
| inner spectral | Float64 128^3 | 4.140 ms | 3.536 ms | 3.107 ms | 2.850 ms | 1.868 ms | 1.074 ms | 708.710 μs | 614.216 μs | 252.487 μs | 203.671 μs |
| inner spectral | Float64 256^3 | 34.526 ms | 29.659 ms | 27.514 ms | 26.111 ms | 18.050 ms | 15.913 ms | 15.339 ms | 15.054 ms | 1.182 ms | 1.115 ms |
| inner spectral | Float64 512^3 | 255.858 ms | 226.744 ms | 211.250 ms | 199.676 ms | 129.955 ms | 129.437 ms | 123.609 ms | 127.806 ms | — | — |
| inner spectral | Float64 64^3 | 309.165 μs | 210.033 μs | 148.238 μs | 127.392 μs | 238.432 μs | 138.952 μs | 87.461 μs | 81.191 μs | 199.280 μs | 85.130 μs |
| inner vec.vec | Float32 128^3 | 1.323 ms | 950.160 μs | 816.944 μs | 711.423 μs | 383.854 μs | 192.341 μs | 99.361 μs | 74.241 μs | 49.104 μs | 30.811 μs |
| inner vec.vec | Float32 256^3 | 13.030 ms | 12.119 ms | 11.438 ms | 10.654 ms | 7.898 ms | 6.055 ms | 5.922 ms | 5.945 ms | 478.617 μs | 488.325 μs |
| inner vec.vec | Float32 512^3 | 104.969 ms | 99.526 ms | 96.158 ms | 89.634 ms | 56.498 ms | 56.952 ms | 55.665 ms | 56.033 ms | — | — |
| inner vec.vec | Float32 64^3 | 69.599 μs | 38.926 μs | 20.420 μs | 14.923 μs | 45.430 μs | 25.710 μs | 14.660 μs | 9.770 μs | 50.158 μs | 13.250 μs |
| inner vec.vec | Float64 128^3 | 2.926 ms | 2.506 ms | 2.293 ms | 2.133 ms | 1.136 ms | 500.295 μs | 301.844 μs | 246.462 μs | 118.997 μs | 135.240 μs |
| inner vec.vec | Float64 256^3 | 25.489 ms | 24.512 ms | 23.201 ms | 22.283 ms | 14.805 ms | 13.708 ms | 13.745 ms | 13.299 ms | 918.815 μs | 965.214 μs |
| inner vec.vec | Float64 512^3 | 212.011 ms | 198.041 ms | 189.067 ms | 178.007 ms | 118.918 ms | 115.063 ms | 110.079 ms | 110.940 ms | — | — |
| inner vec.vec | Float64 64^3 | 136.661 μs | 76.001 μs | 39.834 μs | 25.515 μs | 89.401 μs | 46.430 μs | 27.971 μs | 17.800 μs | 41.269 μs | 20.320 μs |
| integral scalar | Float32 128^3 | 113.205 μs | 61.734 μs | 29.627 μs | 19.984 μs | 59.930 μs | 37.640 μs | 20.091 μs | 12.600 μs | 132.394 μs | 31.720 μs |
| integral scalar | Float32 256^3 | 2.043 ms | 1.488 ms | 1.294 ms | 1.174 ms | 493.215 μs | 318.083 μs | 154.311 μs | 94.461 μs | 616.028 μs | 175.522 μs |
| integral scalar | Float32 512^3 | 19.678 ms | 15.746 ms | 14.784 ms | 14.224 ms | 9.998 ms | 9.160 ms | 9.073 ms | 8.824 ms | — | — |
| integral scalar | Float32 64^3 | 9.752 μs | 6.550 μs | 5.648 μs | 5.799 μs | 6.963 μs | 4.573 μs | 3.871 μs | 4.965 μs | 78.012 μs | 17.930 μs |
| integral scalar | Float64 128^3 | 253.999 μs | 119.139 μs | 66.851 μs | 38.885 μs | 122.311 μs | 64.981 μs | 34.071 μs | 23.580 μs | 149.039 μs | 32.540 μs |
| integral scalar | Float64 256^3 | 4.362 ms | 3.558 ms | 3.275 ms | 3.026 ms | 1.777 ms | 1.006 ms | 822.369 μs | 955.939 μs | 732.824 μs | 191.693 μs |
| integral scalar | Float64 512^3 | 37.576 ms | 32.135 ms | 30.033 ms | 29.174 ms | 19.601 ms | 18.305 ms | 17.958 ms | 18.105 ms | — | — |
| integral scalar | Float64 64^3 | 26.255 μs | 12.381 μs | 8.008 μs | 7.622 μs | 15.050 μs | 7.510 μs | 5.440 μs | 5.700 μs | 77.526 μs | 19.500 μs |
| integral spectral vec | Float32 128^3 | 66.121 ns | 66.808 ns | 67.436 ns | 82.462 ns | 70.707 ns | 68.802 ns | 69.304 ns | 69.335 ns | 82.405 μs | 12.970 μs |
| integral spectral vec | Float32 256^3 | 66.484 ns | 67.441 ns | 67.777 ns | 83.150 ns | 71.209 ns | 69.221 ns | 70.174 ns | 69.631 ns | 73.638 μs | 13.030 μs |
| integral spectral vec | Float32 512^3 | 66.418 ns | 67.951 ns | 67.861 ns | 84.149 ns | 72.778 ns | 72.592 ns | 72.112 ns | 70.502 ns | — | — |
| integral spectral vec | Float32 64^3 | 65.864 ns | 66.969 ns | 66.995 ns | 81.421 ns | 72.596 ns | 68.873 ns | 69.202 ns | 69.683 ns | 78.881 μs | 13.250 μs |
| integral spectral vec | Float64 128^3 | 69.031 ns | 68.348 ns | 69.255 ns | 69.653 ns | 73.717 ns | 72.261 ns | 71.997 ns | 72.246 ns | 73.952 μs | 13.380 μs |
| integral spectral vec | Float64 256^3 | 69.175 ns | 68.795 ns | 69.299 ns | 69.459 ns | 75.262 ns | 74.003 ns | 74.234 ns | 74.071 ns | 73.752 μs | 13.181 μs |
| integral spectral vec | Float64 512^3 | 69.652 ns | 69.119 ns | 70.031 ns | 70.912 ns | 76.182 ns | 77.907 ns | 77.589 ns | 77.443 ns | — | — |
| integral spectral vec | Float64 64^3 | 68.569 ns | 67.415 ns | 67.973 ns | 68.004 ns | 75.783 ns | 74.734 ns | 74.355 ns | 78.013 ns | 81.821 μs | 13.380 μs |
| l2norm vec | Float32 128^3 | 527.126 μs | 314.725 μs | 177.046 μs | 94.345 μs | 242.212 μs | 121.461 μs | 65.791 μs | 37.571 μs | 47.642 μs | 20.390 μs |
| l2norm vec | Float32 256^3 | 7.466 ms | 5.850 ms | 5.401 ms | 4.965 ms | 4.776 ms | 2.704 ms | 1.964 ms | 2.021 ms | 264.733 μs | 258.043 μs |
| l2norm vec | Float32 512^3 | 62.425 ms | 49.766 ms | 46.270 ms | 44.568 ms | 40.699 ms | 30.172 ms | 27.143 ms | 27.120 ms | — | — |
| l2norm vec | Float32 64^3 | 49.336 μs | 27.655 μs | 18.780 μs | 12.689 μs | 31.310 μs | 17.480 μs | 9.740 μs | 7.060 μs | 48.230 μs | 12.460 μs |
| l2norm vec | Float64 128^3 | 1.520 ms | 1.074 ms | 797.428 μs | 711.305 μs | 574.086 μs | 227.782 μs | 122.832 μs | 77.410 μs | 86.147 μs | 54.270 μs |
| l2norm vec | Float64 256^3 | 14.901 ms | 12.033 ms | 11.085 ms | 10.333 ms | 11.032 ms | 6.512 ms | 5.771 ms | 5.689 ms | 532.296 μs | 492.037 μs |
| l2norm vec | Float64 512^3 | 120.359 ms | 99.080 ms | 91.019 ms | 87.536 ms | 66.460 ms | 57.222 ms | 54.515 ms | 54.746 ms | — | — |
| l2norm vec | Float64 64^3 | 92.392 μs | 50.919 μs | 33.041 μs | 18.714 μs | 55.290 μs | 28.761 μs | 16.751 μs | 10.900 μs | 42.664 μs | 20.090 μs |
| lpnorm vec Inf | Float32 128^3 | 1.334 ms | 1.254 ms | 1.087 ms | 947.451 μs | 454.234 μs | 379.252 μs | 324.384 μs | 307.073 μs | 185.653 μs | 66.802 μs |
| lpnorm vec Inf | Float32 256^3 | 13.946 ms | 13.173 ms | 11.556 ms | 10.649 ms | 8.191 ms | 7.989 ms | 7.604 ms | 8.306 ms | 1.070 ms | 509.796 μs |
| lpnorm vec Inf | Float32 512^3 | 114.652 ms | 113.167 ms | 93.098 ms | 85.454 ms | 75.449 ms | 73.189 ms | 72.363 ms | 70.898 ms | — | — |
| lpnorm vec Inf | Float32 64^3 | 96.370 μs | 94.096 μs | 73.549 μs | 84.637 μs | 60.961 μs | 48.880 μs | 41.860 μs | 42.150 μs | 90.800 μs | 24.790 μs |
| lpnorm vec Inf | Float64 128^3 | 3.053 ms | 3.183 ms | 2.631 ms | 2.427 ms | 1.152 ms | 1.075 ms | 945.073 μs | 964.179 μs | 288.572 μs | 127.071 μs |
| lpnorm vec Inf | Float64 256^3 | 27.785 ms | 26.396 ms | 22.963 ms | 21.540 ms | 16.526 ms | 15.903 ms | 15.460 ms | 16.051 ms | 1.913 ms | 957.824 μs |
| lpnorm vec Inf | Float64 512^3 | 223.561 ms | 213.045 ms | 187.236 ms | 172.938 ms | 144.883 ms | 131.127 ms | 138.340 ms | 138.274 ms | — | — |
| lpnorm vec Inf | Float64 64^3 | 233.247 μs | 174.915 μs | 147.324 μs | 136.472 μs | 110.511 μs | 94.601 μs | 76.200 μs | 72.391 μs | 106.389 μs | 37.021 μs |
| maximum scalar | Float32 128^3 | 338.342 μs | 176.640 μs | 92.078 μs | 77.879 μs | 235.342 μs | 116.581 μs | 61.161 μs | 32.750 μs | 135.669 μs | 31.730 μs |
| maximum scalar | Float32 256^3 | 3.407 ms | 1.898 ms | 1.402 ms | 1.188 ms | 1.912 ms | 949.808 μs | 472.555 μs | 239.992 μs | 616.535 μs | 173.622 μs |
| maximum scalar | Float32 512^3 | 24.096 ms | 17.667 ms | 15.267 ms | 14.287 ms | 21.570 ms | 12.244 ms | 9.291 ms | 8.187 ms | — | — |
| maximum scalar | Float32 64^3 | 42.020 μs | 24.577 μs | 13.945 μs | 11.582 μs | 29.410 μs | 16.090 μs | 9.311 μs | 6.640 μs | 78.495 μs | 18.230 μs |
| maximum scalar | Float64 128^3 | 565.846 μs | 278.395 μs | 143.150 μs | 133.460 μs | 441.364 μs | 222.122 μs | 113.261 μs | 59.461 μs | 172.935 μs | 40.980 μs |
| maximum scalar | Float64 256^3 | 6.135 ms | 3.934 ms | 3.395 ms | 3.044 ms | 4.020 ms | 2.044 ms | 1.034 ms | 806.328 μs | 972.353 μs | 214.823 μs |
| maximum scalar | Float64 512^3 | 48.714 ms | 33.445 ms | 30.564 ms | 29.127 ms | 44.532 ms | 26.088 ms | 18.725 ms | 17.395 ms | — | — |
| maximum scalar | Float64 64^3 | 65.250 μs | 36.625 μs | 21.048 μs | 14.741 μs | 55.290 μs | 29.241 μs | 15.960 μs | 9.970 μs | 80.807 μs | 24.240 μs |
| maximum(norm) vec | Float32 128^3 | 1.799 ms | 947.000 μs | 474.822 μs | 245.647 μs | 777.577 μs | 391.482 μs | 198.372 μs | 101.991 μs | 194.976 μs | 42.061 μs |
| maximum(norm) vec | Float32 256^3 | 15.151 ms | 8.169 ms | 5.709 ms | 5.004 ms | 7.309 ms | 3.817 ms | 2.141 ms | 2.132 ms | 852.612 μs | 283.253 μs |
| maximum(norm) vec | Float32 512^3 | 118.979 ms | 67.746 ms | 49.904 ms | 45.549 ms | 59.757 ms | 37.417 ms | 29.436 ms | 28.486 ms | — | — |
| maximum(norm) vec | Float32 64^3 | 220.737 μs | 116.548 μs | 61.320 μs | 74.226 μs | 96.471 μs | 49.371 μs | 26.351 μs | 15.381 μs | 91.731 μs | 20.220 μs |
| maximum(norm) vec | Float64 128^3 | 5.214 ms | 2.699 ms | 1.383 ms | 823.695 μs | 1.586 ms | 794.308 μs | 400.095 μs | 204.662 μs | 252.937 μs | 143.650 μs |
| maximum(norm) vec | Float64 256^3 | 42.183 ms | 21.531 ms | 12.660 ms | 11.079 ms | 14.953 ms | 7.898 ms | 6.060 ms | 5.688 ms | 1.624 ms | 972.444 μs |
| maximum(norm) vec | Float64 512^3 | 336.030 ms | 171.441 ms | 106.202 ms | 92.733 ms | 114.067 ms | 70.962 ms | 56.004 ms | 56.424 ms | — | — |
| maximum(norm) vec | Float64 64^3 | 638.858 μs | 329.832 μs | 168.017 μs | 90.193 μs | 197.022 μs | 101.661 μs | 52.240 μs | 28.440 μs | 99.986 μs | 35.710 μs |
| mean spectral vec | Float32 128^3 | 68.912 ns | 70.049 ns | 70.289 ns | 70.490 ns | 72.616 ns | 71.899 ns | 71.822 ns | 71.399 ns | 79.850 μs | 12.940 μs |
| mean spectral vec | Float32 256^3 | 69.607 ns | 70.568 ns | 70.640 ns | 70.658 ns | 72.709 ns | 73.430 ns | 72.766 ns | 71.994 ns | 79.489 μs | 12.930 μs |
| mean spectral vec | Float32 512^3 | 70.361 ns | 74.360 ns | 70.561 ns | 72.088 ns | 74.093 ns | 76.043 ns | 75.454 ns | 72.591 ns | — | — |
| mean spectral vec | Float32 64^3 | 69.389 ns | 70.450 ns | 69.490 ns | 69.618 ns | 74.173 ns | 71.778 ns | 71.633 ns | 75.283 ns | 82.207 μs | 13.270 μs |
| mean spectral vec | Float64 128^3 | 71.489 ns | 72.792 ns | 72.690 ns | 72.359 ns | 75.966 ns | 77.088 ns | 77.170 ns | 79.156 ns | 79.575 μs | 13.270 μs |
| mean spectral vec | Float64 256^3 | 72.023 ns | 72.870 ns | 72.888 ns | 73.692 ns | 77.586 ns | 78.295 ns | 78.524 ns | 76.724 ns | 73.475 μs | 13.390 μs |
| mean spectral vec | Float64 512^3 | 72.260 ns | 79.126 ns | 73.249 ns | 74.082 ns | 78.565 ns | 82.147 ns | 83.240 ns | 80.528 ns | — | — |
| mean spectral vec | Float64 64^3 | 71.541 ns | 71.722 ns | 71.249 ns | 70.881 ns | 78.854 ns | 79.287 ns | 79.391 ns | 81.458 ns | 81.598 μs | 13.380 μs |
| mean vector | Float32 128^3 | 436.861 μs | 275.585 μs | 172.486 μs | 97.294 μs | 195.582 μs | 105.881 μs | 60.901 μs | 47.501 μs | 402.046 μs | 97.112 μs |
| mean vector | Float32 256^3 | 6.719 ms | 5.740 ms | 5.323 ms | 5.010 ms | 3.659 ms | 2.482 ms | 2.390 ms | 2.487 ms | 1.854 ms | 530.666 μs |
| mean vector | Float32 512^3 | 58.139 ms | 48.680 ms | 44.902 ms | 43.607 ms | 33.734 ms | 28.143 ms | 27.269 ms | 27.357 ms | — | — |
| mean vector | Float32 64^3 | 41.575 μs | 28.263 μs | 19.642 μs | 22.649 μs | 24.500 μs | 16.161 μs | 13.320 μs | 15.970 μs | 233.114 μs | 55.520 μs |
| mean vector | Float64 128^3 | 1.368 ms | 933.480 μs | 770.661 μs | 717.190 μs | 400.734 μs | 195.272 μs | 112.181 μs | 83.691 μs | 436.590 μs | 105.750 μs |
| mean vector | Float64 256^3 | 14.052 ms | 11.870 ms | 11.077 ms | 10.448 ms | 7.506 ms | 6.299 ms | 6.627 ms | 6.767 ms | 2.206 ms | 579.239 μs |
| mean vector | Float64 512^3 | 113.193 ms | 97.006 ms | 90.840 ms | 87.788 ms | 58.554 ms | 55.177 ms | 54.344 ms | 54.865 ms | — | — |
| mean vector | Float64 64^3 | 84.427 μs | 48.544 μs | 30.783 μs | 29.104 μs | 46.141 μs | 28.240 μs | 19.460 μs | 18.960 μs | 242.233 μs | 59.780 μs |
| mean(det) tensor | Float32 128^3 | 2.417 ms | 1.854 ms | 1.598 ms | 1.497 ms | 778.917 μs | 355.861 μs | 199.593 μs | 124.651 μs | 188.881 μs | 113.352 μs |
| mean(det) tensor | Float32 256^3 | 21.277 ms | 20.099 ms | 18.172 ms | 17.264 ms | 15.981 ms | 10.762 ms | 10.361 ms | 10.380 ms | 1.105 ms | 745.948 μs |
| mean(det) tensor | Float32 512^3 | 172.153 ms | 163.945 ms | 149.988 ms | 143.179 ms | 106.970 ms | 89.104 ms | 86.013 ms | 84.340 ms | — | — |
| mean(det) tensor | Float32 64^3 | 104.177 μs | 54.345 μs | 28.867 μs | 21.326 μs | 67.271 μs | 36.350 μs | 20.060 μs | 15.890 μs | 85.536 μs | 24.980 μs |
| mean(det) tensor | Float64 128^3 | 5.149 ms | 4.545 ms | 3.887 ms | 3.631 ms | 2.552 ms | 1.513 ms | 1.196 ms | 1.179 ms | 258.338 μs | 203.861 μs |
| mean(det) tensor | Float64 256^3 | 41.379 ms | 40.368 ms | 37.887 ms | 35.177 ms | 24.723 ms | 21.900 ms | 21.469 ms | 21.585 ms | 1.686 ms | 1.447 ms |
| mean(det) tensor | Float64 512^3 | 325.205 ms | 326.577 ms | 300.634 ms | 283.598 ms | 203.393 ms | 179.181 ms | 169.143 ms | 169.566 ms | — | — |
| mean(det) tensor | Float64 64^3 | 224.659 μs | 127.893 μs | 74.006 μs | 38.604 μs | 129.451 μs | 68.401 μs | 36.790 μs | 28.860 μs | 90.194 μs | 32.720 μs |
| mean(norm) vec | Float32 128^3 | 1.550 ms | 812.954 μs | 406.340 μs | 213.901 μs | 610.776 μs | 302.982 μs | 155.092 μs | 80.861 μs | 241.001 μs | 42.311 μs |
| mean(norm) vec | Float32 256^3 | 12.965 ms | 7.522 ms | 5.637 ms | 4.998 ms | 6.847 ms | 3.532 ms | 2.060 ms | 2.140 ms | 848.973 μs | 281.173 μs |
| mean(norm) vec | Float32 512^3 | 101.664 ms | 63.563 ms | 49.462 ms | 45.365 ms | 52.300 ms | 35.372 ms | 29.225 ms | 28.361 ms | — | — |
| mean(norm) vec | Float32 64^3 | 189.160 μs | 100.213 μs | 52.956 μs | 67.516 μs | 75.780 μs | 39.330 μs | 21.230 μs | 12.800 μs | 87.347 μs | 20.451 μs |
| mean(norm) vec | Float64 128^3 | 5.147 ms | 2.663 ms | 1.349 ms | 830.769 μs | 1.437 ms | 723.358 μs | 364.805 μs | 187.671 μs | 236.768 μs | 127.371 μs |
| mean(norm) vec | Float64 256^3 | 41.522 ms | 21.232 ms | 12.635 ms | 11.159 ms | 13.743 ms | 8.020 ms | 5.809 ms | 5.673 ms | 1.371 ms | 867.173 μs |
| mean(norm) vec | Float64 512^3 | 331.193 ms | 168.941 ms | 105.211 ms | 92.581 ms | 105.540 ms | 68.214 ms | 55.763 ms | 56.347 ms | — | — |
| mean(norm) vec | Float64 64^3 | 631.535 μs | 326.034 μs | 168.591 μs | 88.614 μs | 179.561 μs | 92.851 μs | 47.800 μs | 26.110 μs | 97.683 μs | 31.411 μs |
| mean(tr) tensor | Float32 128^3 | 399.009 μs | 245.872 μs | 147.045 μs | 59.212 μs | 195.542 μs | 96.231 μs | 51.301 μs | 37.030 μs | 146.458 μs | 40.061 μs |
| mean(tr) tensor | Float32 256^3 | 6.131 ms | 5.862 ms | 5.338 ms | 4.961 ms | 3.221 ms | 2.227 ms | 2.161 ms | 2.199 ms | 715.643 μs | 275.083 μs |
| mean(tr) tensor | Float32 512^3 | 51.993 ms | 49.935 ms | 47.562 ms | 45.092 ms | 33.179 ms | 28.901 ms | 28.402 ms | 27.741 ms | — | — |
| mean(tr) tensor | Float32 64^3 | 35.048 μs | 18.580 μs | 11.830 μs | 10.177 μs | 24.961 μs | 12.290 μs | 7.720 μs | 6.481 μs | 77.980 μs | 21.040 μs |
| mean(tr) tensor | Float64 128^3 | 1.280 ms | 949.800 μs | 800.417 μs | 692.895 μs | 387.363 μs | 186.352 μs | 93.921 μs | 73.751 μs | 162.643 μs | 53.360 μs |
| mean(tr) tensor | Float64 256^3 | 12.499 ms | 11.853 ms | 11.372 ms | 10.742 ms | 6.225 ms | 6.326 ms | 6.333 ms | 6.276 ms | 878.142 μs | 500.858 μs |
| mean(tr) tensor | Float64 512^3 | 104.298 ms | 100.708 ms | 95.066 ms | 88.987 ms | 66.526 ms | 61.397 ms | 56.092 ms | 56.449 ms | — | — |
| mean(tr) tensor | Float64 64^3 | 66.817 μs | 37.152 μs | 19.666 μs | 15.579 μs | 42.841 μs | 24.290 μs | 13.870 μs | 9.460 μs | 83.085 μs | 22.470 μs |
| radial_correlation vec | Float32 128^3 | 35.571 ms | 31.061 ms | 32.612 ms | 33.624 ms | 30.274 ms | 22.048 ms | 21.062 ms | 20.809 ms | 709.383 μs | 548.973 μs |
| radial_correlation vec | Float32 256^3 | 395.970 ms | 314.312 ms | 262.237 ms | 252.597 ms | 386.875 ms | 195.806 ms | 184.514 ms | 172.728 ms | 10.395 ms | 6.610 ms |
| radial_correlation vec | Float32 512^3 | 3.675 s | 2.544 s | 1.847 s | 1.613 s | 2.774 s | 1.794 s | 1.346 s | 1.109 s | — | — |
| radial_correlation vec | Float32 64^3 | 4.240 ms | 5.099 ms | 5.427 ms | 5.669 ms | 3.547 ms | 3.338 ms | 3.680 ms | 3.646 ms | 207.811 μs | 146.820 μs |
| radial_correlation vec | Float64 128^3 | 56.335 ms | 54.616 ms | 40.099 ms | 53.887 ms | 39.107 ms | 29.249 ms | 31.686 ms | 29.859 ms | 36.483 ms | 1.934 ms |
| radial_correlation vec | Float64 256^3 | 566.203 ms | 448.656 ms | 331.754 ms | 311.984 ms | 540.656 ms | 364.353 ms | 260.793 ms | 236.134 ms | 146.621 ms | 14.572 ms |
| radial_correlation vec | Float64 512^3 | 5.581 s | 3.664 s | 2.900 s | 2.448 s | 4.309 s | 2.822 s | 2.011 s | 1.713 s | — | — |
| radial_correlation vec | Float64 64^3 | 5.404 ms | 5.254 ms | 5.408 ms | 5.205 ms | 3.839 ms | 3.263 ms | 3.272 ms | 3.245 ms | 12.963 ms | 243.601 μs |
| radial_spectrum vec | Float32 128^3 | 7.479 ms | 6.857 ms | 8.635 ms | 8.641 ms | 6.328 ms | 4.746 ms | 5.714 ms | 5.960 ms | 324.002 μs | 172.104 μs |
| radial_spectrum vec | Float32 256^3 | 59.601 ms | 42.973 ms | 45.793 ms | 44.093 ms | 50.089 ms | 33.922 ms | 31.245 ms | 32.924 ms | 914.928 μs | 824.470 μs |
| radial_spectrum vec | Float32 512^3 | 474.263 ms | 342.922 ms | 255.081 ms | 223.928 ms | 399.621 ms | 238.040 ms | 180.443 ms | 153.226 ms | — | — |
| radial_spectrum vec | Float32 64^3 | 983.294 μs | 1.382 ms | 1.620 ms | 1.671 ms | 822.088 μs | 908.749 μs | 1.136 ms | 1.396 ms | 218.318 μs | 71.511 μs |
| radial_spectrum vec | Float64 128^3 | 7.569 ms | 5.352 ms | 6.003 ms | 6.026 ms | 6.557 ms | 4.579 ms | 4.419 ms | 4.247 ms | 17.742 ms | 251.601 μs |
| radial_spectrum vec | Float64 256^3 | 60.230 ms | 44.482 ms | 35.347 ms | 30.127 ms | 52.024 ms | 32.141 ms | 25.430 ms | 24.137 ms | 54.973 ms | 1.144 ms |
| radial_spectrum vec | Float64 512^3 | 483.046 ms | 338.977 ms | 217.670 ms | 173.729 ms | 412.693 ms | 247.564 ms | 163.608 ms | 123.757 ms | — | — |
| radial_spectrum vec | Float64 64^3 | 973.498 μs | 917.307 μs | 1.154 ms | 1.081 ms | 852.429 μs | 688.857 μs | 830.728 μs | 974.669 μs | 7.040 ms | 77.750 μs |
| reality_residual scalar | Float32 128^3 | 229.590 μs | 230.235 μs | 231.314 μs | 230.178 μs | 179.640 μs | 181.372 μs | 179.881 μs | 179.491 μs | 243.074 μs | 91.911 μs |
| reality_residual scalar | Float32 256^3 | 1.021 ms | 1.017 ms | 1.024 ms | 1.021 ms | 718.514 μs | 732.256 μs | 721.377 μs | 715.106 μs | 226.455 μs | 87.601 μs |
| reality_residual scalar | Float32 512^3 | 8.106 ms | 8.105 ms | 8.193 ms | 8.774 ms | 2.899 ms | 2.921 ms | 2.905 ms | 2.903 ms | — | — |
| reality_residual scalar | Float32 64^3 | 52.255 μs | 53.161 μs | 52.676 μs | 53.005 μs | 45.880 μs | 46.300 μs | 45.261 μs | 45.780 μs | 233.619 μs | 86.851 μs |
| reality_residual scalar | Float64 128^3 | 362.209 μs | 364.248 μs | 366.130 μs | 365.554 μs | 367.231 μs | 367.583 μs | 367.423 μs | 367.763 μs | 244.213 μs | 103.091 μs |
| reality_residual scalar | Float64 256^3 | 1.586 ms | 1.601 ms | 1.606 ms | 1.588 ms | 1.478 ms | 1.479 ms | 1.479 ms | 1.472 ms | 237.865 μs | 104.431 μs |
| reality_residual scalar | Float64 512^3 | 13.258 ms | 13.518 ms | 12.854 ms | 14.542 ms | 6.040 ms | 6.114 ms | 6.083 ms | 6.037 ms | — | — |
| reality_residual scalar | Float64 64^3 | 80.166 μs | 80.354 μs | 79.998 μs | 80.595 μs | 92.061 μs | 90.830 μs | 91.240 μs | 90.951 μs | 238.317 μs | 99.330 μs |
| reality_residual vector | Float32 128^3 | 787.510 μs | 788.210 μs | 788.489 μs | 788.956 μs | 648.903 μs | 654.015 μs | 649.606 μs | 648.716 μs | 254.669 μs | 95.291 μs |
| reality_residual vector | Float32 256^3 | 5.309 ms | 5.388 ms | 5.287 ms | 5.486 ms | 2.587 ms | 2.589 ms | 2.595 ms | 2.597 ms | 280.762 μs | 97.851 μs |
| reality_residual vector | Float32 512^3 | 33.746 ms | 31.920 ms | 33.465 ms | 32.539 ms | 16.041 ms | 16.187 ms | 16.123 ms | 16.174 ms | — | — |
| reality_residual vector | Float32 64^3 | 182.910 μs | 183.396 μs | 182.505 μs | 182.786 μs | 162.462 μs | 162.231 μs | 164.371 μs | 162.891 μs | 246.476 μs | 89.621 μs |
| reality_residual vector | Float64 128^3 | 1.247 ms | 1.253 ms | 1.255 ms | 1.263 ms | 1.258 ms | 1.254 ms | 1.257 ms | 1.263 ms | 256.991 μs | 104.551 μs |
| reality_residual vector | Float64 256^3 | 9.072 ms | 8.904 ms | 9.152 ms | 8.978 ms | 5.069 ms | 5.042 ms | 5.053 ms | 5.043 ms | 293.711 μs | 123.612 μs |
| reality_residual vector | Float64 512^3 | 47.403 ms | 47.563 ms | 47.786 ms | 58.024 ms | 35.440 ms | 35.587 ms | 35.587 ms | 35.374 ms | — | — |
| reality_residual vector | Float64 64^3 | 273.417 μs | 273.923 μs | 274.979 μs | 277.967 μs | 312.903 μs | 311.912 μs | 312.442 μs | 312.283 μs | 254.978 μs | 100.231 μs |
| var scalar | Float32 128^3 | 234.246 μs | 129.282 μs | 70.053 μs | 44.985 μs | 132.871 μs | 77.200 μs | 40.920 μs | 26.890 μs | 266.090 μs | 64.811 μs |
| var scalar | Float32 256^3 | 4.152 ms | 3.120 ms | 2.626 ms | 2.433 ms | 1.065 ms | 670.735 μs | 313.013 μs | 194.912 μs | 1.227 ms | 352.834 μs |
| var scalar | Float32 512^3 | 39.003 ms | 31.677 ms | 29.871 ms | 28.628 ms | 25.406 ms | 19.833 ms | 18.231 ms | 17.829 ms | — | — |
| var scalar | Float32 64^3 | 24.247 μs | 16.574 μs | 11.813 μs | 14.166 μs | 14.940 μs | 8.430 μs | 7.170 μs | 9.360 μs | 150.119 μs | 36.980 μs |
| var scalar | Float64 128^3 | 546.656 μs | 248.252 μs | 136.036 μs | 84.573 μs | 253.912 μs | 130.681 μs | 69.411 μs | 49.711 μs | 308.131 μs | 69.860 μs |
| var scalar | Float64 256^3 | 8.784 ms | 7.375 ms | 6.561 ms | 6.126 ms | 3.874 ms | 2.169 ms | 1.666 ms | 1.794 ms | 1.544 ms | 393.266 μs |
| var scalar | Float64 512^3 | 74.897 ms | 64.156 ms | 60.257 ms | 58.039 ms | 43.491 ms | 37.549 ms | 36.293 ms | 36.231 ms | — | — |
| var scalar | Float64 64^3 | 53.158 μs | 26.763 μs | 17.054 μs | 16.591 μs | 31.190 μs | 16.520 μs | 11.330 μs | 11.000 μs | 152.416 μs | 40.540 μs |
| var spectral scalar | Float32 128^3 | 131.168 μs | 90.581 μs | 63.026 μs | 55.036 μs | 90.981 μs | 59.491 μs | 43.250 μs | 38.990 μs | 256.148 μs | 64.231 μs |
| var spectral scalar | Float32 256^3 | 2.159 ms | 1.790 ms | 1.552 ms | 1.474 ms | 675.587 μs | 453.394 μs | 270.643 μs | 243.703 μs | 468.446 μs | 149.462 μs |
| var spectral scalar | Float32 512^3 | 19.896 ms | 17.643 ms | 16.883 ms | 16.393 ms | 13.108 ms | 10.460 ms | 10.656 ms | 10.782 ms | — | — |
| var spectral scalar | Float32 64^3 | 16.419 μs | 12.591 μs | 10.007 μs | 12.277 μs | 11.680 μs | 8.080 μs | 7.870 μs | 7.760 μs | 222.796 μs | 57.340 μs |
| var spectral scalar | Float64 128^3 | 267.726 μs | 183.123 μs | 110.537 μs | 84.526 μs | 145.761 μs | 87.680 μs | 62.010 μs | 58.980 μs | 264.955 μs | 72.380 μs |
| var spectral scalar | Float64 256^3 | 4.616 ms | 3.930 ms | 3.673 ms | 3.451 ms | 2.066 ms | 1.494 ms | 1.020 ms | 1.083 ms | 573.817 μs | 233.884 μs |
| var spectral scalar | Float64 512^3 | 39.258 ms | 34.734 ms | 33.293 ms | 31.746 ms | 21.074 ms | 20.593 ms | 20.172 ms | 20.532 ms | — | — |
| var spectral scalar | Float64 64^3 | 30.313 μs | 21.561 μs | 14.706 μs | 14.849 μs | 20.070 μs | 12.920 μs | 9.610 μs | 9.910 μs | 209.456 μs | 59.461 μs |
| weighted_inner vec | Float32 128^3 | 12.300 ms | 12.395 ms | 12.375 ms | 12.296 ms | 10.381 ms | 10.368 ms | 10.418 ms | 10.409 ms | 257.603 μs | 74.931 μs |
| weighted_inner vec | Float32 256^3 | 96.624 ms | 97.458 ms | 97.449 ms | 96.646 ms | 81.460 ms | 81.522 ms | 81.532 ms | 81.168 ms | 1.438 ms | 555.116 μs |
| weighted_inner vec | Float32 512^3 | 766.351 ms | 773.793 ms | 772.446 ms | 766.855 ms | 646.088 ms | 645.574 ms | 647.615 ms | 648.225 ms | — | — |
| weighted_inner vec | Float32 64^3 | 1.590 ms | 1.595 ms | 1.595 ms | 1.592 ms | 1.280 ms | 1.283 ms | 1.340 ms | 1.290 ms | 112.844 μs | 26.870 μs |
| weighted_inner vec | Float64 128^3 | 13.342 ms | 13.467 ms | 13.435 ms | 13.474 ms | 10.933 ms | 10.867 ms | 10.917 ms | 10.891 ms | 299.135 μs | 101.600 μs |
| weighted_inner vec | Float64 256^3 | 106.185 ms | 107.134 ms | 106.782 ms | 107.247 ms | 85.874 ms | 85.820 ms | 85.917 ms | 85.803 ms | 1.812 ms | 984.295 μs |
| weighted_inner vec | Float64 512^3 | 839.428 ms | 849.395 ms | 847.598 ms | 850.121 ms | 681.537 ms | 681.187 ms | 682.825 ms | 682.128 ms | — | — |
| weighted_inner vec | Float64 64^3 | 1.679 ms | 1.690 ms | 1.687 ms | 1.687 ms | 1.370 ms | 1.349 ms | 1.409 ms | 1.407 ms | 121.037 μs | 30.941 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.348 ms | 12.463 ms | 12.439 ms | 12.347 ms | 10.435 ms | 10.341 ms | 10.484 ms | 10.379 ms | 260.055 μs | 90.102 μs |
| weighted_inner vec.vec | Float32 256^3 | 97.135 ms | 97.591 ms | 97.453 ms | 96.992 ms | 81.590 ms | 81.646 ms | 81.748 ms | 81.562 ms | 1.452 ms | 747.108 μs |
| weighted_inner vec.vec | Float32 512^3 | 769.535 ms | 774.431 ms | 777.825 ms | 771.400 ms | 642.701 ms | 647.487 ms | 659.758 ms | 649.760 ms | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.593 ms | 1.598 ms | 1.599 ms | 1.592 ms | 1.290 ms | 1.299 ms | 1.349 ms | 1.288 ms | 115.713 μs | 27.070 μs |
| weighted_inner vec.vec | Float64 128^3 | 13.591 ms | 13.697 ms | 13.706 ms | 13.796 ms | 10.960 ms | 10.954 ms | 10.954 ms | 11.011 ms | 300.598 μs | 179.011 μs |
| weighted_inner vec.vec | Float64 256^3 | 107.934 ms | 108.859 ms | 109.570 ms | 109.514 ms | 86.033 ms | 85.984 ms | 86.241 ms | 86.194 ms | 1.830 ms | 1.460 ms |
| weighted_inner vec.vec | Float64 512^3 | 852.141 ms | 862.464 ms | 861.115 ms | 866.634 ms | 695.526 ms | 683.394 ms | 697.655 ms | 780.013 ms | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.688 ms | 1.705 ms | 1.690 ms | 1.695 ms | 1.420 ms | 1.399 ms | 1.421 ms | 1.454 ms | 122.263 μs | 30.390 μs |
| weighted_inner x3 fused | Float32 128^3 | 32.408 ms | 32.342 ms | 32.307 ms | 32.320 ms | 23.389 ms | 23.365 ms | 23.252 ms | 23.433 ms | 333.088 μs | 122.991 μs |
| weighted_inner x3 fused | Float32 256^3 | 258.895 ms | 258.294 ms | 258.512 ms | 258.681 ms | 184.948 ms | 184.899 ms | 183.419 ms | 184.914 ms | 1.924 ms | 868.359 μs |
| weighted_inner x3 fused | Float32 512^3 | 2.062 s | 2.058 s | 2.059 s | 2.060 s | 1.470 s | 1.469 s | 1.462 s | 1.470 s | — | — |
| weighted_inner x3 fused | Float32 64^3 | 4.034 ms | 4.040 ms | 4.042 ms | 4.040 ms | 2.929 ms | 2.924 ms | 2.924 ms | 2.980 ms | 131.713 μs | 36.000 μs |
| weighted_inner x3 fused | Float64 128^3 | 32.208 ms | 32.161 ms | 32.154 ms | 32.140 ms | 23.034 ms | 23.400 ms | 23.380 ms | 23.076 ms | 508.608 μs | 243.462 μs |
| weighted_inner x3 fused | Float64 256^3 | 254.749 ms | 254.516 ms | 254.069 ms | 254.135 ms | 181.949 ms | 185.287 ms | 185.246 ms | 182.524 ms | 3.346 ms | 1.708 ms |
| weighted_inner x3 fused | Float64 512^3 | 2.065 s | 2.021 s | 2.022 s | 2.022 s | 1.447 s | 1.473 s | 1.471 s | 1.478 s | — | — |
| weighted_inner x3 fused | Float64 64^3 | 4.017 ms | 4.015 ms | 4.018 ms | 4.018 ms | 2.897 ms | 2.941 ms | 2.892 ms | 2.901 ms | 150.050 μs | 54.681 μs |
| weighted_inner x3 separate | Float32 128^3 | 53.173 ms | 53.112 ms | 53.029 ms | 53.013 ms | 42.350 ms | 42.836 ms | 42.907 ms | 42.596 ms | 793.494 μs | 257.652 μs |
| weighted_inner x3 separate | Float32 256^3 | 427.028 ms | 425.948 ms | 426.191 ms | 425.830 ms | 336.910 ms | 337.589 ms | 346.283 ms | 334.165 ms | 4.764 ms | 1.702 ms |
| weighted_inner x3 separate | Float32 512^3 | 3.397 s | 3.388 s | 3.378 s | 3.380 s | 2.660 s | 2.685 s | 2.742 s | 2.664 s | — | — |
| weighted_inner x3 separate | Float32 64^3 | 6.721 ms | 6.721 ms | 6.716 ms | 6.713 ms | 5.333 ms | 5.398 ms | 5.542 ms | 5.478 ms | 338.765 μs | 89.340 μs |
| weighted_inner x3 separate | Float64 128^3 | 54.580 ms | 54.549 ms | 54.521 ms | 54.592 ms | 44.576 ms | 43.981 ms | 43.871 ms | 43.792 ms | 1.018 ms | 363.643 μs |
| weighted_inner x3 separate | Float64 256^3 | 436.824 ms | 436.344 ms | 436.518 ms | 436.292 ms | 358.628 ms | 347.715 ms | 347.077 ms | 346.465 ms | 6.212 ms | 2.322 ms |
| weighted_inner x3 separate | Float64 512^3 | 3.488 s | 3.483 s | 3.472 s | 3.467 s | 2.812 s | 2.753 s | 2.744 s | 2.742 s | — | — |
| weighted_inner x3 separate | Float64 64^3 | 6.919 ms | 6.922 ms | 6.923 ms | 6.911 ms | 5.524 ms | 5.602 ms | 5.482 ms | 5.463 ms | 405.573 μs | 105.431 μs |

## storage

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| adapt multipliers | Float32 128^3 | — | — | — | — | — | — | — | — | 140.997 μs | 13.300 μs |
| adapt multipliers | Float32 256^3 | — | — | — | — | — | — | — | — | 146.386 μs | 13.350 μs |
| adapt multipliers | Float32 64^3 | — | — | — | — | — | — | — | — | 147.447 μs | 13.180 μs |
| adapt multipliers | Float64 128^3 | — | — | — | — | — | — | — | — | 146.471 μs | 13.260 μs |
| adapt multipliers | Float64 256^3 | — | — | — | — | — | — | — | — | 150.846 μs | 12.860 μs |
| adapt multipliers | Float64 64^3 | — | — | — | — | — | — | — | — | 152.508 μs | 13.220 μs |
| adapt plans (rebuild) | Float32 128^3 | — | — | — | — | — | — | — | — | 12.586 μs | 7.620 μs |
| adapt plans (rebuild) | Float32 256^3 | — | — | — | — | — | — | — | — | 60.577 μs | 23.470 μs |
| adapt plans (rebuild) | Float32 64^3 | — | — | — | — | — | — | — | — | 10.112 μs | 7.390 μs |
| adapt plans (rebuild) | Float64 128^3 | — | — | — | — | — | — | — | — | 18.780 μs | 8.270 μs |
| adapt plans (rebuild) | Float64 256^3 | — | — | — | — | — | — | — | — | 58.671 μs | 54.550 μs |
| adapt plans (rebuild) | Float64 64^3 | — | — | — | — | — | — | — | — | 10.139 μs | 7.510 μs |
| adapt to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 655.642 μs | 308.713 μs |
| adapt to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.659 ms | 2.460 ms |
| adapt to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 188.894 μs | 61.160 μs |
| adapt to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.304 ms | 595.115 μs |
| adapt to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 11.416 ms | 6.032 ms |
| adapt to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 176.581 μs | 94.171 μs |
| adapt to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.955 ms | 885.329 μs |
| adapt to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 16.659 ms | 8.996 ms |
| adapt to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 262.057 μs | 132.452 μs |
| adapt to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 4.354 ms | 1.758 ms |
| adapt to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 32.419 ms | 19.767 ms |
| adapt to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 514.347 μs | 237.982 μs |
| adapt to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 514.156 μs | 419.894 μs |
| adapt to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 12.909 ms | 11.410 ms |
| adapt to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 145.539 μs | 62.631 μs |
| adapt to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.040 ms | 829.678 μs |
| adapt to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 24.400 ms | 23.723 ms |
| adapt to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 132.708 μs | 112.371 μs |
| adapt to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.573 ms | 1.238 ms |
| adapt to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 35.319 ms | 36.273 ms |
| adapt to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 196.167 μs | 164.262 μs |
| adapt to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 9.559 ms | 8.518 ms |
| adapt to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 70.098 ms | 72.177 ms |
| adapt to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 391.320 μs | 318.083 μs |
| adapt to own family (identity) | Float32 128^3 | — | — | — | — | — | — | — | — | 145.095 ns | 118.219 ns |
| adapt to own family (identity) | Float32 256^3 | — | — | — | — | — | — | — | — | 145.762 ns | 118.912 ns |
| adapt to own family (identity) | Float32 64^3 | — | — | — | — | — | — | — | — | 143.551 ns | 118.651 ns |
| adapt to own family (identity) | Float64 128^3 | — | — | — | — | — | — | — | — | 159.363 ns | 118.516 ns |
| adapt to own family (identity) | Float64 256^3 | — | — | — | — | — | — | — | — | 156.538 ns | 122.140 ns |
| adapt to own family (identity) | Float64 64^3 | — | — | — | — | — | — | — | — | 155.749 ns | 118.714 ns |
| adapt! to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 649.287 μs | 305.813 μs |
| adapt! to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.276 ms | 2.415 ms |
| adapt! to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 175.639 μs | 59.060 μs |
| adapt! to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.297 ms | 591.096 μs |
| adapt! to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 10.582 ms | 5.761 ms |
| adapt! to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 171.649 μs | 91.701 μs |
| adapt! to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.948 ms | 877.049 μs |
| adapt! to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 15.883 ms | 9.124 ms |
| adapt! to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 256.862 μs | 128.181 μs |
| adapt! to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.988 ms | 1.747 ms |
| adapt! to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 31.641 ms | 18.312 ms |
| adapt! to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 511.339 μs | 233.532 μs |
| adapt! to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 521.190 μs | 416.014 μs |
| adapt! to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 4.294 ms | 3.276 ms |
| adapt! to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 126.685 μs | 61.871 μs |
| adapt! to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.048 ms | 821.847 μs |
| adapt! to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 8.147 ms | 6.598 ms |
| adapt! to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 135.976 μs | 112.651 μs |
| adapt! to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.560 ms | 1.228 ms |
| adapt! to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 12.638 ms | 9.918 ms |
| adapt! to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 199.243 μs | 162.901 μs |
| adapt! to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.121 ms | 2.446 ms |
| adapt! to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 25.120 ms | 19.732 ms |
| adapt! to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 395.344 μs | 315.453 μs |

