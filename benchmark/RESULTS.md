# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-08-05 at commit `264e9da8` on Julia 1.12.6, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–256³) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The pre-swap archive columns (GTX 1070, RX 6700 XT) keep their pre-rewrite measurements — retired hardware is not re-swept; every live column (both CPUs, RX 7900 XTX, RTX 5070 Ti) is measured at the decision-38/39 rewrite. **`fft` rows are comparable only within a column vintage.** The 2026-08-05 re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows of the same lanes moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. See PERFORMANCE.md §4(p). A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field. Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `264e9da8 @ 2026-08-05`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI; `48b6254a @ 2026-07-22`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8; `5934a78c @ 2026-07-22`: GPU 7900XTX; unstamped (vintage in the prose above): GPU 1070, GPU 6700XT. ~10% jitter.

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 4.029 ms | 2.979 ms | 2.144 ms | 2.286 ms | 2.785 ms | 1.468 ms | 825.039 μs | 526.065 μs | — | — | — | — |
| to_physical scalar measure | Float32 256^3 | 70.669 ms | 39.135 ms | 41.008 ms | 38.313 ms | 31.963 ms | 20.675 ms | 14.102 ms | 11.900 ms | — | — | — | — |
| to_physical scalar measure | Float32 512^3 | — | — | — | — | 359.936 ms | 196.036 ms | 145.811 ms | 131.356 ms | — | — | — | — |
| to_physical scalar measure | Float32 64^3 | 379.762 μs | 239.143 μs | 166.345 μs | 174.205 μs | 278.443 μs | 158.871 μs | 95.491 μs | 68.460 μs | — | — | — | — |
| to_physical scalar measure | Float64 128^3 | 6.339 ms | 5.666 ms | 5.246 ms | 4.657 ms | 3.966 ms | 2.459 ms | 1.450 ms | 1.164 ms | — | — | — | — |
| to_physical scalar measure | Float64 256^3 | 130.934 ms | 77.228 ms | 81.269 ms | 80.228 ms | 107.025 ms | 42.443 ms | 33.597 ms | 42.895 ms | — | — | — | — |
| to_physical scalar measure | Float64 512^3 | — | — | — | — | 874.242 ms | 585.630 ms | 449.228 ms | 400.750 ms | — | — | — | — |
| to_physical scalar measure | Float64 64^3 | 550.138 μs | 384.916 μs | 254.230 μs | 269.289 μs | 373.384 μs | 207.822 μs | 133.082 μs | 101.711 μs | — | — | — | — |
| to_physical scalar | Float32 128^3 | 5.090 ms | 3.355 ms | 2.501 ms | 2.307 ms | 4.526 ms | 2.401 ms | 1.279 ms | 780.589 μs | 788.067 μs | 2.421 ms | 1.261 ms | 124.222 μs |
| to_physical scalar | Float32 256^3 | 121.444 ms | 68.555 ms | 51.504 ms | 42.019 ms | 167.481 ms | 89.002 ms | 48.071 ms | 28.070 ms | — | 7.945 ms | 2.307 ms | 1.092 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | 2.032 s | 1.014 s | 557.968 ms | 323.605 ms | — | — | 13.398 ms | — |
| to_physical scalar | Float32 64^3 | 393.312 μs | 254.738 μs | 177.742 μs | 169.864 μs | 317.583 μs | 175.832 μs | 102.451 μs | 69.781 μs | 124.402 μs | 1.497 ms | 1.071 ms | 111.732 μs |
| to_physical scalar | Float64 128^3 | 8.120 ms | 5.823 ms | 4.940 ms | 4.470 ms | 10.016 ms | 5.395 ms | 3.045 ms | 1.833 ms | 1.905 ms | 3.750 ms | 1.646 ms | 518.486 μs |
| to_physical scalar | Float64 256^3 | 153.418 ms | 86.677 ms | 84.769 ms | 78.209 ms | 116.009 ms | 49.727 ms | 35.835 ms | 41.326 ms | — | 14.463 ms | 5.748 ms | 3.856 ms |
| to_physical scalar | Float64 512^3 | — | — | — | — | 947.813 ms | 622.876 ms | 453.709 ms | 411.141 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 702.253 μs | 432.399 μs | 307.892 μs | 258.256 μs | 536.156 μs | 289.402 μs | 165.602 μs | 115.671 μs | 331.873 μs | 1.784 ms | 992.328 μs | 115.001 μs |
| to_physical vector measure | Float32 128^3 | 12.766 ms | 9.673 ms | 8.916 ms | 7.915 ms | 9.415 ms | 5.765 ms | 4.042 ms | 3.109 ms | — | — | — | — |
| to_physical vector measure | Float32 256^3 | 214.079 ms | 158.244 ms | 131.321 ms | 124.027 ms | 122.127 ms | 82.642 ms | 56.883 ms | 50.480 ms | — | — | — | — |
| to_physical vector measure | Float32 512^3 | — | — | — | — | 1.414 s | 991.823 ms | 726.002 ms | 636.295 ms | — | — | — | — |
| to_physical vector measure | Float32 64^3 | 1.243 ms | 846.687 μs | 565.090 μs | 477.502 μs | 876.529 μs | 496.044 μs | 299.443 μs | 223.762 μs | — | — | — | — |
| to_physical vector measure | Float64 128^3 | 39.710 ms | 19.225 ms | 24.054 ms | 28.588 ms | 22.716 ms | 17.022 ms | 13.803 ms | 13.878 ms | — | — | — | — |
| to_physical vector measure | Float64 256^3 | 394.501 ms | 287.104 ms | 246.423 ms | 233.583 ms | 333.875 ms | 223.494 ms | 171.643 ms | 152.791 ms | — | — | — | — |
| to_physical vector measure | Float64 512^3 | — | — | — | — | 2.593 s | 1.791 s | 1.364 s | 1.214 s | — | — | — | — |
| to_physical vector measure | Float64 64^3 | 2.216 ms | 1.775 ms | 1.270 ms | 1.164 ms | 1.119 ms | 682.937 μs | 417.264 μs | 346.084 μs | — | — | — | — |
| to_physical vector | Float32 128^3 | 15.103 ms | 11.836 ms | 8.416 ms | 7.502 ms | 14.547 ms | 10.047 ms | 5.498 ms | 3.994 ms | 2.507 ms | 4.595 ms | 1.724 ms | 303.383 μs |
| to_physical vector | Float32 256^3 | 365.291 ms | 269.022 ms | 173.624 ms | 151.640 ms | 530.370 ms | 362.577 ms | 189.015 ms | 135.163 ms | — | 14.844 ms | 5.773 ms | 3.483 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | 6.317 s | 4.303 s | 2.323 s | 1.656 s | — | — | 51.336 ms | — |
| to_physical vector | Float32 64^3 | 1.306 ms | 1.045 ms | 596.992 μs | 550.376 μs | 1.011 ms | 679.717 μs | 319.633 μs | 221.832 μs | 380.054 μs | 1.776 ms | 1.186 ms | 129.711 μs |
| to_physical vector | Float64 128^3 | 46.428 ms | 20.507 ms | 26.548 ms | 27.522 ms | 40.341 ms | 28.484 ms | 19.360 ms | 16.772 ms | 5.630 ms | 8.090 ms | 2.788 ms | 1.490 ms |
| to_physical vector | Float64 256^3 | 460.818 ms | 358.235 ms | 260.213 ms | 241.545 ms | 357.403 ms | 272.826 ms | 176.757 ms | 156.240 ms | — | 22.812 ms | 13.720 ms | 11.385 ms |
| to_physical vector | Float64 512^3 | — | — | — | — | 2.810 s | 2.143 s | 1.423 s | 1.275 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.619 ms | 2.147 ms | 1.646 ms | 1.216 ms | 1.668 ms | 1.146 ms | 578.566 μs | 423.715 μs | 811.437 μs | 2.301 ms | 1.271 ms | 203.792 μs |
| to_spectral scalar measure | Float32 128^3 | 3.676 ms | 2.364 ms | 1.542 ms | 1.608 ms | 2.798 ms | 1.424 ms | 787.478 μs | 478.735 μs | — | — | — | — |
| to_spectral scalar measure | Float32 256^3 | 64.792 ms | 32.427 ms | 35.643 ms | 32.348 ms | 36.744 ms | 21.261 ms | 13.615 ms | 10.554 ms | — | — | — | — |
| to_spectral scalar measure | Float32 512^3 | — | — | — | — | 369.629 ms | 171.988 ms | 113.206 ms | 98.470 ms | — | — | — | — |
| to_spectral scalar measure | Float32 64^3 | 365.235 μs | 209.243 μs | 132.354 μs | 137.319 μs | 279.603 μs | 146.462 μs | 85.271 μs | 57.180 μs | — | — | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.417 ms | 4.397 ms | 3.789 ms | 3.542 ms | 3.870 ms | 2.396 ms | 1.511 ms | 894.330 μs | — | — | — | — |
| to_spectral scalar measure | Float64 256^3 | 125.027 ms | 67.875 ms | 71.203 ms | 65.713 ms | 93.751 ms | 40.189 ms | 26.642 ms | 31.053 ms | — | — | — | — |
| to_spectral scalar measure | Float64 512^3 | — | — | — | — | 772.885 ms | 509.036 ms | 383.774 ms | 332.050 ms | — | — | — | — |
| to_spectral scalar measure | Float64 64^3 | 488.909 μs | 307.927 μs | 233.393 μs | 155.459 μs | 347.094 μs | 190.351 μs | 114.911 μs | 74.781 μs | — | — | — | — |
| to_spectral scalar | Float32 128^3 | 4.631 ms | 2.783 ms | 1.829 ms | 1.359 ms | 4.489 ms | 2.309 ms | 1.252 ms | 739.548 μs | 488.254 μs | 2.072 ms | 1.113 ms | 99.241 μs |
| to_spectral scalar | Float32 256^3 | 116.450 ms | 64.693 ms | 48.096 ms | 36.889 ms | 167.145 ms | 87.126 ms | 46.049 ms | 26.208 ms | — | 5.009 ms | 1.905 ms | 748.598 μs |
| to_spectral scalar | Float32 512^3 | — | — | — | — | 1.959 s | 982.890 ms | 515.588 ms | 290.158 ms | — | — | 9.591 ms | — |
| to_spectral scalar | Float32 64^3 | 372.359 μs | 214.769 μs | 131.392 μs | 113.455 μs | 306.333 μs | 164.582 μs | 90.661 μs | 59.350 μs | 89.181 μs | 1.538 ms | 1.110 ms | 79.591 μs |
| to_spectral scalar | Float64 128^3 | 7.266 ms | 5.156 ms | 3.900 ms | 3.492 ms | 9.960 ms | 5.640 ms | 2.995 ms | 1.677 ms | 1.501 ms | 3.125 ms | 1.651 ms | 452.815 μs |
| to_spectral scalar | Float64 256^3 | 174.719 ms | 98.673 ms | 79.881 ms | 67.152 ms | 207.406 ms | 91.751 ms | 53.049 ms | 46.783 ms | — | 12.871 ms | 5.179 ms | 3.135 ms |
| to_spectral scalar | Float64 512^3 | — | — | — | — | 1.712 s | 974.684 ms | 601.319 ms | 434.228 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 660.845 μs | 375.644 μs | 246.524 μs | 187.733 μs | 516.766 μs | 274.303 μs | 153.801 μs | 96.421 μs | 265.683 μs | 1.745 ms | 1.077 ms | 103.951 μs |
| to_spectral vector measure | Float32 128^3 | 11.048 ms | 7.840 ms | 6.309 ms | 5.676 ms | 9.863 ms | 5.945 ms | 3.568 ms | 2.711 ms | — | — | — | — |
| to_spectral vector measure | Float32 256^3 | 194.942 ms | 138.599 ms | 108.318 ms | 104.246 ms | 130.782 ms | 77.203 ms | 47.618 ms | 41.221 ms | — | — | — | — |
| to_spectral vector measure | Float32 512^3 | — | — | — | — | 1.401 s | 904.170 ms | 636.487 ms | 530.718 ms | — | — | — | — |
| to_spectral vector measure | Float32 64^3 | 1.133 ms | 709.014 μs | 489.066 μs | 410.465 μs | 883.499 μs | 480.625 μs | 264.803 μs | 199.102 μs | — | — | — | — |
| to_spectral vector measure | Float64 128^3 | 36.748 ms | 15.038 ms | 18.304 ms | 13.894 ms | 23.967 ms | 17.468 ms | 13.240 ms | 13.115 ms | — | — | — | — |
| to_spectral vector measure | Float64 256^3 | 378.151 ms | 266.528 ms | 209.729 ms | 202.722 ms | 289.988 ms | 198.167 ms | 138.329 ms | 125.640 ms | — | — | — | — |
| to_spectral vector measure | Float64 512^3 | — | — | — | — | 2.247 s | 1.534 s | 1.163 s | 984.517 ms | — | — | — | — |
| to_spectral vector measure | Float64 64^3 | 1.673 ms | 1.521 ms | 887.037 μs | 648.760 μs | 1.061 ms | 649.717 μs | 374.813 μs | 275.723 μs | — | — | — | — |
| to_spectral vector | Float32 128^3 | 14.075 ms | 9.864 ms | 6.814 ms | 5.884 ms | 14.586 ms | 10.454 ms | 5.014 ms | 3.559 ms | 1.355 ms | 3.183 ms | 1.354 ms | 198.662 μs |
| to_spectral vector | Float32 256^3 | 353.409 ms | 258.328 ms | 153.782 ms | 128.389 ms | 522.037 ms | 352.782 ms | 177.434 ms | 123.615 ms | — | 11.819 ms | 3.512 ms | 2.215 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | 6.251 s | 4.283 s | 2.239 s | 1.570 s | — | — | 20.305 ms | — |
| to_spectral vector | Float32 64^3 | 1.296 ms | 931.449 μs | 509.295 μs | 432.093 μs | 971.561 μs | 652.406 μs | 285.753 μs | 181.042 μs | 230.522 μs | 1.566 ms | 924.065 μs | 94.591 μs |
| to_spectral vector | Float64 128^3 | 43.494 ms | 18.891 ms | 23.457 ms | 13.411 ms | 41.049 ms | 30.695 ms | 19.224 ms | 16.661 ms | 4.144 ms | 6.538 ms | 2.420 ms | 1.180 ms |
| to_spectral vector | Float64 256^3 | 515.584 ms | 385.138 ms | 244.471 ms | 223.678 ms | 634.829 ms | 450.086 ms | 252.364 ms | 197.484 ms | — | 20.041 ms | 11.730 ms | 9.226 ms |
| to_spectral vector | Float64 512^3 | — | — | — | — | 5.124 s | 3.636 s | 2.044 s | 1.600 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.288 ms | 1.711 ms | 1.039 ms | 825.169 μs | 1.564 ms | 1.086 ms | 532.105 μs | 347.664 μs | 596.836 μs | 2.151 ms | 1.215 ms | 208.532 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 415.446 μs | 232.867 μs | 171.971 μs | 72.717 μs | 161.342 μs | 83.991 μs | 43.720 μs | 36.420 μs | 351.303 μs | 1.943 ms | 1.146 ms | 81.390 μs |
| add! scalar | Float32 256^3 | 8.457 ms | 7.574 ms | 5.893 ms | 5.483 ms | 3.479 ms | 2.948 ms | 2.727 ms | 2.807 ms | — | 6.480 ms | 1.935 ms | 329.123 μs |
| add! scalar | Float32 512^3 | — | — | — | — | 40.681 ms | 36.541 ms | 36.661 ms | 37.270 ms | — | — | 7.478 ms | — |
| add! scalar | Float32 64^3 | 43.141 μs | 21.824 μs | 10.651 μs | 8.520 μs | 22.621 μs | 12.771 μs | 7.010 μs | 6.350 μs | 85.391 μs | 1.599 ms | 1.040 ms | 70.130 μs |
| add! scalar | Float64 128^3 | 1.551 ms | 1.347 ms | 1.009 ms | 866.257 μs | 320.173 μs | 163.672 μs | 87.861 μs | 72.281 μs | 354.693 μs | 2.024 ms | 1.185 ms | 100.541 μs |
| add! scalar | Float64 256^3 | 17.701 ms | 15.946 ms | 12.391 ms | 11.679 ms | 10.097 ms | 8.732 ms | 8.338 ms | 8.529 ms | — | 5.550 ms | 1.863 ms | 562.466 μs |
| add! scalar | Float64 512^3 | — | — | — | — | 84.255 ms | 73.021 ms | 73.450 ms | 74.194 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 85.390 μs | 49.484 μs | 21.892 μs | 16.987 μs | 39.791 μs | 22.740 μs | 12.030 μs | 9.820 μs | 83.741 μs | 1.494 ms | 1.042 ms | 58.210 μs |
| combine! vec | Float32 128^3 | 2.791 ms | 2.491 ms | 1.937 ms | 1.731 ms | 632.417 μs | 324.984 μs | 162.262 μs | 112.461 μs | — | — | 1.460 ms | 186.562 μs |
| combine! vec | Float32 256^3 | 26.616 ms | 24.004 ms | 18.893 ms | 17.671 ms | 13.778 ms | 13.637 ms | 13.738 ms | 13.953 ms | — | — | 4.150 ms | 1.017 ms |
| combine! vec | Float32 512^3 | — | — | — | — | 116.665 ms | 106.896 ms | 110.713 ms | 111.740 ms | — | — | 19.880 ms | — |
| combine! vec | Float32 64^3 | 129.345 μs | 71.185 μs | 38.072 μs | 19.846 μs | 66.031 μs | 34.531 μs | 20.580 μs | 14.371 μs | — | — | 1.124 ms | 74.231 μs |
| combine! vec | Float64 128^3 | 6.186 ms | 5.637 ms | 4.316 ms | 4.084 ms | 2.241 ms | 1.868 ms | 1.547 ms | 1.517 ms | — | — | 1.695 ms | 258.423 μs |
| combine! vec | Float64 256^3 | 53.020 ms | 48.164 ms | 37.890 ms | 35.457 ms | 28.298 ms | 26.631 ms | 27.010 ms | 27.738 ms | — | — | 4.922 ms | 1.593 ms |
| combine! vec | Float64 512^3 | — | — | — | — | 226.533 ms | 219.380 ms | 218.729 ms | 221.268 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 269.387 μs | 146.932 μs | 80.411 μs | 45.637 μs | 122.971 μs | 64.360 μs | 34.381 μs | 28.571 μs | — | — | 1.119 ms | 65.860 μs |
| cross! | Float32 128^3 | 3.081 ms | 2.621 ms | 2.296 ms | 2.180 ms | 1.986 ms | 970.939 μs | 479.095 μs | 250.383 μs | 1.223 ms | 3.445 ms | 1.087 ms | 127.131 μs |
| cross! | Float32 256^3 | 28.931 ms | 26.586 ms | 24.325 ms | 23.702 ms | 24.035 ms | 14.378 ms | 12.381 ms | 12.442 ms | — | 14.690 ms | 1.775 ms | 830.189 μs |
| cross! | Float32 512^3 | — | — | — | — | 190.976 ms | 116.522 ms | 111.647 ms | 111.178 ms | — | — | 7.558 ms | — |
| cross! | Float32 64^3 | 262.350 μs | 129.860 μs | 72.659 μs | 39.588 μs | 235.972 μs | 115.681 μs | 59.851 μs | 32.890 μs | 219.582 μs | 1.665 ms | 1.031 ms | 59.271 μs |
| cross! | Float64 128^3 | 6.532 ms | 6.049 ms | 5.442 ms | 5.440 ms | 3.792 ms | 2.317 ms | 1.580 ms | 1.492 ms | 1.263 ms | 2.603 ms | 1.367 ms | 278.063 μs |
| cross! | Float64 256^3 | 58.605 ms | 53.033 ms | 49.389 ms | 46.968 ms | 42.542 ms | 29.897 ms | 27.020 ms | 27.256 ms | — | 15.625 ms | 2.733 ms | 1.595 ms |
| cross! | Float64 512^3 | — | — | — | — | 316.778 ms | 232.816 ms | 220.539 ms | 220.836 ms | — | — | — | — |
| cross! | Float64 64^3 | 373.469 μs | 187.020 μs | 101.539 μs | 53.528 μs | 225.132 μs | 115.861 μs | 59.500 μs | 36.241 μs | 216.592 μs | 1.846 ms | 1.103 ms | 65.651 μs |
| det! tensor | Float32 128^3 | 3.660 ms | 2.587 ms | 2.160 ms | 1.966 ms | 2.166 ms | 1.081 ms | 547.135 μs | 290.473 μs | — | — | 1.218 ms | 184.282 μs |
| det! tensor | Float32 256^3 | 36.447 ms | 25.949 ms | 23.192 ms | 21.245 ms | 30.909 ms | 18.014 ms | 12.000 ms | 11.942 ms | — | — | 2.219 ms | 912.229 μs |
| det! tensor | Float32 512^3 | — | — | — | — | 211.147 ms | 124.395 ms | 104.433 ms | 104.939 ms | — | — | 9.408 ms | — |
| det! tensor | Float32 64^3 | 361.565 μs | 186.619 μs | 83.056 μs | 46.689 μs | 255.553 μs | 128.791 μs | 65.551 μs | 36.401 μs | — | — | 966.709 μs | 78.881 μs |
| det! tensor | Float64 128^3 | 6.753 ms | 5.973 ms | 4.837 ms | 4.566 ms | 4.005 ms | 2.560 ms | 1.685 ms | 1.609 ms | — | — | 1.460 ms | 260.493 μs |
| det! tensor | Float64 256^3 | 54.980 ms | 52.857 ms | 43.163 ms | 39.883 ms | 41.957 ms | 29.101 ms | 25.715 ms | 25.576 ms | — | — | 2.941 ms | 1.816 ms |
| det! tensor | Float64 512^3 | — | — | — | — | 409.421 ms | 246.752 ms | 206.794 ms | 209.257 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 363.147 μs | 220.005 μs | 110.514 μs | 60.662 μs | 253.163 μs | 152.552 μs | 75.091 μs | 42.051 μs | — | — | 1.071 ms | 67.921 μs |
| dot! vec.vec | Float32 128^3 | 2.899 ms | 1.731 ms | 1.349 ms | 1.223 ms | 2.453 ms | 1.246 ms | 626.926 μs | 322.663 μs | 538.855 μs | 2.430 ms | 1.239 ms | 112.321 μs |
| dot! vec.vec | Float32 256^3 | 24.982 ms | 18.857 ms | 15.827 ms | 15.018 ms | 22.526 ms | 11.397 ms | 8.105 ms | 8.032 ms | — | 9.651 ms | 2.506 ms | 667.826 μs |
| dot! vec.vec | Float32 512^3 | — | — | — | — | 170.914 ms | 92.426 ms | 76.011 ms | 76.057 ms | — | — | 11.342 ms | — |
| dot! vec.vec | Float32 64^3 | 336.093 μs | 201.695 μs | 106.726 μs | 61.308 μs | 308.574 μs | 159.962 μs | 81.741 μs | 44.040 μs | 112.901 μs | 1.663 ms | 1.107 ms | 68.330 μs |
| dot! vec.vec | Float64 128^3 | 4.596 ms | 3.946 ms | 3.317 ms | 3.108 ms | 3.493 ms | 1.737 ms | 887.879 μs | 639.157 μs | 618.906 μs | 2.505 ms | 1.223 ms | 193.872 μs |
| dot! vec.vec | Float64 256^3 | 44.072 ms | 36.289 ms | 30.450 ms | 28.480 ms | 36.896 ms | 19.597 ms | 17.904 ms | 17.997 ms | — | 9.784 ms | 2.819 ms | 1.218 ms |
| dot! vec.vec | Float64 512^3 | — | — | — | — | 228.498 ms | 158.762 ms | 148.040 ms | 151.292 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 342.485 μs | 207.767 μs | 108.330 μs | 66.523 μs | 317.754 μs | 159.121 μs | 81.631 μs | 44.221 μs | 127.611 μs | 1.656 ms | 1.019 ms | 62.510 μs |
| map!(+) vec | Float32 128^3 | — | — | — | — | 1.611 ms | 807.878 μs | 400.584 μs | 208.092 μs | — | — | — | 120.721 μs |
| map!(+) vec | Float32 256^3 | — | — | — | — | 21.415 ms | 14.028 ms | 12.396 ms | 12.455 ms | — | — | — | 829.909 μs |
| map!(+) vec | Float32 512^3 | — | — | — | — | 179.107 ms | 115.435 ms | 111.688 ms | 111.266 ms | — | — | — | — |
| map!(+) vec | Float32 64^3 | — | — | — | — | 175.802 μs | 95.001 μs | 48.590 μs | 27.490 μs | — | — | — | 55.801 μs |
| map!(+) vec | Float64 128^3 | — | — | — | — | 3.717 ms | 2.254 ms | 1.564 ms | 1.506 ms | — | — | — | 279.963 μs |
| map!(+) vec | Float64 256^3 | — | — | — | — | 39.252 ms | 29.601 ms | 27.023 ms | 27.288 ms | — | — | — | 1.600 ms |
| map!(+) vec | Float64 512^3 | — | — | — | — | 309.853 ms | 226.512 ms | 221.559 ms | 219.295 ms | — | — | — | — |
| map!(+) vec | Float64 64^3 | — | — | — | — | 199.612 μs | 94.581 μs | 48.501 μs | 31.940 μs | — | — | — | 63.831 μs |
| map!(det) tensor | Float32 128^3 | — | — | — | — | 2.151 ms | 1.081 ms | 547.785 μs | 286.693 μs | — | — | — | 181.881 μs |
| map!(det) tensor | Float32 256^3 | — | — | — | — | 30.749 ms | 18.289 ms | 12.020 ms | 11.953 ms | — | — | — | 884.889 μs |
| map!(det) tensor | Float32 512^3 | — | — | — | — | 215.387 ms | 124.185 ms | 104.338 ms | 105.084 ms | — | — | — | — |
| map!(det) tensor | Float32 64^3 | — | — | — | — | 251.253 μs | 127.811 μs | 65.521 μs | 36.231 μs | — | — | — | 71.431 μs |
| map!(det) tensor | Float64 128^3 | — | — | — | — | 3.999 ms | 2.486 ms | 1.679 ms | 1.607 ms | — | — | — | 266.122 μs |
| map!(det) tensor | Float64 256^3 | — | — | — | — | 41.941 ms | 28.988 ms | 25.660 ms | 26.193 ms | — | — | — | 1.830 ms |
| map!(det) tensor | Float64 512^3 | — | — | — | — | 398.621 ms | 237.563 ms | 206.237 ms | 208.857 ms | — | — | — | — |
| map!(det) tensor | Float64 64^3 | — | — | — | — | 251.632 μs | 129.851 μs | 66.161 μs | 42.151 μs | — | — | — | 75.380 μs |
| mul! tensor.vec | Float32 128^3 | 5.241 ms | 4.508 ms | 4.097 ms | 3.891 ms | 3.368 ms | 1.971 ms | 1.060 ms | 766.088 μs | 1.525 ms | 4.295 ms | 1.202 ms | 208.463 μs |
| mul! tensor.vec | Float32 256^3 | 56.838 ms | 41.730 ms | 39.368 ms | 37.470 ms | 32.923 ms | 28.940 ms | 20.935 ms | 20.943 ms | — | 16.892 ms | 2.504 ms | 1.315 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | 347.679 ms | 215.344 ms | 178.840 ms | 175.320 ms | — | — | 12.936 ms | — |
| mul! tensor.vec | Float32 64^3 | 628.537 μs | 242.475 μs | 121.446 μs | 68.588 μs | 372.604 μs | 212.232 μs | 107.341 μs | 58.021 μs | 255.702 μs | 1.882 ms | 1.051 ms | 74.300 μs |
| mul! tensor.vec | Float64 128^3 | 11.484 ms | 10.231 ms | 9.209 ms | 9.025 ms | 7.015 ms | 5.490 ms | 4.516 ms | 4.313 ms | 1.748 ms | 4.757 ms | 1.469 ms | 394.614 μs |
| mul! tensor.vec | Float64 256^3 | 90.503 ms | 85.167 ms | 77.262 ms | 74.028 ms | 57.331 ms | 50.796 ms | 43.292 ms | 43.693 ms | — | 17.818 ms | 3.896 ms | 2.568 ms |
| mul! tensor.vec | Float64 512^3 | — | — | — | — | 574.679 ms | 384.477 ms | 346.964 ms | 346.037 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 695.993 μs | 473.800 μs | 359.566 μs | 211.291 μs | 377.394 μs | 214.922 μs | 109.261 μs | 60.791 μs | 280.183 μs | 1.951 ms | 1.082 ms | 79.781 μs |
| norm! vec | Float32 128^3 | 746.619 μs | 599.150 μs | 478.282 μs | 359.445 μs | 215.802 μs | 116.272 μs | 62.621 μs | 54.290 μs | 411.304 μs | 2.110 ms | 1.077 ms | 87.961 μs |
| norm! vec | Float32 256^3 | 10.798 ms | 10.148 ms | 8.212 ms | 7.831 ms | 5.312 ms | 4.313 ms | 4.113 ms | 4.239 ms | — | 7.304 ms | 2.143 ms | 392.964 μs |
| norm! vec | Float32 512^3 | — | — | — | — | 53.474 ms | 46.026 ms | 46.323 ms | 46.766 ms | — | — | 7.958 ms | — |
| norm! vec | Float32 64^3 | 54.472 μs | 38.606 μs | 20.836 μs | 16.505 μs | 32.151 μs | 20.990 μs | 12.990 μs | 11.351 μs | 100.251 μs | 1.526 ms | 1.029 ms | 53.610 μs |
| norm! vec | Float64 128^3 | 2.313 ms | 2.021 ms | 1.631 ms | 1.458 ms | 475.805 μs | 247.272 μs | 130.861 μs | 103.532 μs | 463.344 μs | 1.434 ms | 1.433 ms | 177.462 μs |
| norm! vec | Float64 256^3 | 22.327 ms | 20.362 ms | 16.905 ms | 15.982 ms | 11.860 ms | 10.276 ms | 10.240 ms | 10.511 ms | — | 9.850 ms | 3.294 ms | 718.727 μs |
| norm! vec | Float64 512^3 | — | — | — | — | 98.096 ms | 91.879 ms | 91.944 ms | 93.394 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 160.911 μs | 91.195 μs | 50.848 μs | 32.368 μs | 56.541 μs | 34.910 μs | 20.910 μs | 16.131 μs | 101.231 μs | 1.681 ms | 1.117 ms | 66.380 μs |
| tr! tensor | Float32 128^3 | 714.866 μs | 548.546 μs | 465.762 μs | 349.269 μs | 213.522 μs | 113.371 μs | 59.850 μs | 50.970 μs | — | — | 1.021 ms | 85.880 μs |
| tr! tensor | Float32 256^3 | 10.668 ms | 9.839 ms | 8.090 ms | 7.701 ms | 5.143 ms | 4.389 ms | 4.285 ms | 4.395 ms | — | — | 1.859 ms | 390.684 μs |
| tr! tensor | Float32 512^3 | — | — | — | — | 48.439 ms | 45.246 ms | 46.314 ms | 46.857 ms | — | — | 8.577 ms | — |
| tr! tensor | Float32 64^3 | 53.777 μs | 34.817 μs | 16.681 μs | 14.213 μs | 27.520 μs | 18.070 μs | 11.310 μs | 9.240 μs | — | — | 1.108 ms | 70.371 μs |
| tr! tensor | Float64 128^3 | 2.278 ms | 1.979 ms | 1.580 ms | 1.405 ms | 459.104 μs | 237.062 μs | 123.722 μs | 99.031 μs | — | — | 1.153 ms | 118.612 μs |
| tr! tensor | Float64 256^3 | 21.191 ms | 19.901 ms | 16.409 ms | 15.480 ms | 11.679 ms | 10.572 ms | 10.558 ms | 10.700 ms | — | — | 2.035 ms | 725.297 μs |
| tr! tensor | Float64 512^3 | — | — | — | — | 105.082 ms | 91.770 ms | 92.929 ms | 94.273 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 107.137 μs | 64.410 μs | 34.513 μs | 22.760 μs | 53.781 μs | 31.390 μs | 18.790 μs | 13.990 μs | — | — | 1.004 ms | 57.131 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.644 ms | 2.884 ms | 1.570 ms | 1.284 ms | 3.206 ms | 1.657 ms | 835.459 μs | 427.495 μs | 697.807 μs | 2.544 ms | 1.114 ms | 96.391 μs |
| curl! vec->vec | Float32 256^3 | 47.565 ms | 23.207 ms | 18.167 ms | 17.606 ms | 25.705 ms | 13.142 ms | 8.876 ms | 8.782 ms | — | 10.865 ms | 1.562 ms | 603.926 μs |
| curl! vec->vec | Float32 512^3 | — | — | — | — | 206.734 ms | 108.282 ms | 84.698 ms | 83.799 ms | — | — | 6.384 ms | — |
| curl! vec->vec | Float32 64^3 | 715.869 μs | 361.298 μs | 185.059 μs | 97.663 μs | 417.165 μs | 216.872 μs | 109.911 μs | 58.010 μs | 182.902 μs | 1.646 ms | 1.026 ms | 67.821 μs |
| curl! vec->vec | Float64 128^3 | 5.732 ms | 4.247 ms | 3.988 ms | 3.859 ms | 3.699 ms | 1.861 ms | 951.380 μs | 538.286 μs | 824.588 μs | 3.153 ms | 1.535 ms | 209.672 μs |
| curl! vec->vec | Float64 256^3 | 48.543 ms | 38.387 ms | 36.437 ms | 35.207 ms | 32.969 ms | 20.119 ms | 19.345 ms | 20.601 ms | — | 13.647 ms | 3.147 ms | 1.123 ms |
| curl! vec->vec | Float64 512^3 | — | — | — | — | 238.336 ms | 165.155 ms | 164.326 ms | 165.950 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 685.445 μs | 351.104 μs | 180.555 μs | 96.016 μs | 469.475 μs | 237.312 μs | 115.842 μs | 64.781 μs | 186.242 μs | 1.786 ms | 1.155 ms | 78.651 μs |
| divergence! vec->scalar | Float32 128^3 | 3.583 ms | 1.379 ms | 726.007 μs | 414.664 μs | 3.349 ms | 1.120 ms | 557.196 μs | 291.933 μs | 326.353 μs | 1.957 ms | 1.144 ms | 90.970 μs |
| divergence! vec->scalar | Float32 256^3 | 29.383 ms | 11.815 ms | 9.639 ms | 9.114 ms | 26.643 ms | 8.971 ms | 4.540 ms | 4.136 ms | — | 5.523 ms | 1.734 ms | 407.894 μs |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | 211.213 ms | 70.610 ms | 46.833 ms | 46.802 ms | — | — | 6.985 ms | — |
| divergence! vec->scalar | Float32 64^3 | 427.482 μs | 176.505 μs | 93.067 μs | 51.431 μs | 434.305 μs | 151.492 μs | 78.480 μs | 42.921 μs | 93.900 μs | 1.537 ms | 971.404 μs | 64.510 μs |
| divergence! vec->scalar | Float64 128^3 | 3.927 ms | 2.101 ms | 1.724 ms | 1.552 ms | 3.332 ms | 1.082 ms | 536.115 μs | 273.273 μs | 407.644 μs | 2.306 ms | 1.190 ms | 129.981 μs |
| divergence! vec->scalar | Float64 256^3 | 32.045 ms | 22.048 ms | 17.831 ms | 16.405 ms | 27.143 ms | 11.131 ms | 10.313 ms | 10.251 ms | — | 7.090 ms | 2.578 ms | 747.328 μs |
| divergence! vec->scalar | Float64 512^3 | — | — | — | — | 211.819 ms | 95.607 ms | 92.961 ms | 93.073 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 444.337 μs | 163.080 μs | 87.120 μs | 53.950 μs | 436.625 μs | 141.861 μs | 71.341 μs | 40.820 μs | 103.111 μs | 344.869 μs | 982.625 μs | 67.061 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.411 ms | 1.797 ms | 988.567 μs | 683.645 μs | 4.946 ms | 2.045 ms | 1.020 ms | 527.695 μs | — | — | 1.230 ms | 100.051 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 36.347 ms | 14.813 ms | 12.158 ms | 11.437 ms | 39.536 ms | 16.116 ms | 8.119 ms | 4.262 ms | — | — | 2.109 ms | 416.114 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | — | — | — | — | 311.793 ms | 126.956 ms | 63.952 ms | 46.892 ms | — | — | 7.652 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 539.303 μs | 233.316 μs | 134.678 μs | 71.987 μs | 635.487 μs | 271.503 μs | 138.771 μs | 74.511 μs | — | — | 1.103 ms | 65.301 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.877 ms | 2.753 ms | 2.260 ms | 2.157 ms | 4.968 ms | 1.991 ms | 978.730 μs | 510.916 μs | — | — | 1.365 ms | 165.302 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 39.931 ms | 26.505 ms | 21.953 ms | 20.596 ms | 39.905 ms | 15.865 ms | 10.327 ms | 10.276 ms | — | — | 2.922 ms | 744.908 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | — | — | — | — | 311.790 ms | 123.354 ms | 93.777 ms | 93.248 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 533.393 μs | 216.600 μs | 115.672 μs | 70.444 μs | 636.917 μs | 257.132 μs | 131.121 μs | 70.881 μs | — | — | 1.163 ms | 76.001 μs |
| gradient! scalar->vec | Float32 128^3 | 3.262 ms | 1.702 ms | 880.984 μs | 532.987 μs | 1.956 ms | 973.410 μs | 489.695 μs | 255.323 μs | 560.525 μs | 2.377 ms | 1.076 ms | 85.561 μs |
| gradient! scalar->vec | Float32 256^3 | 26.249 ms | 15.053 ms | 13.785 ms | 13.763 ms | 15.628 ms | 7.811 ms | 5.648 ms | 5.642 ms | — | 7.929 ms | 1.569 ms | 441.394 μs |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | 124.510 ms | 66.098 ms | 63.587 ms | 64.217 ms | — | — | 4.394 ms | — |
| gradient! scalar->vec | Float32 64^3 | 415.585 μs | 221.863 μs | 107.430 μs | 58.414 μs | 248.293 μs | 125.971 μs | 63.910 μs | 34.800 μs | 133.261 μs | 1.681 ms | 1.016 ms | 56.630 μs |
| gradient! scalar->vec | Float64 128^3 | 3.461 ms | 2.907 ms | 2.635 ms | 2.547 ms | 2.068 ms | 990.610 μs | 488.485 μs | 255.383 μs | 605.225 μs | 2.717 ms | 1.313 ms | 159.132 μs |
| gradient! scalar->vec | Float64 256^3 | 32.069 ms | 29.672 ms | 28.081 ms | 27.512 ms | 20.256 ms | 14.697 ms | 13.993 ms | 14.102 ms | — | 10.338 ms | 2.498 ms | 806.689 μs |
| gradient! scalar->vec | Float64 512^3 | — | — | — | — | 154.953 ms | 128.469 ms | 127.527 ms | 128.432 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 368.859 μs | 192.400 μs | 94.043 μs | 56.623 μs | 262.483 μs | 125.061 μs | 63.261 μs | 34.170 μs | 153.172 μs | 1.872 ms | 1.022 ms | 68.831 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.405 ms | 2.303 ms | 1.399 ms | 1.289 ms | 3.376 ms | 1.688 ms | 854.709 μs | 443.815 μs | 1.480 ms | 4.174 ms | 1.196 ms | 95.961 μs |
| helmholtz! vec->vec | Float32 256^3 | 36.655 ms | 19.651 ms | 18.114 ms | 17.670 ms | 26.844 ms | 13.392 ms | 8.556 ms | 8.570 ms | — | 16.637 ms | 1.739 ms | 605.806 μs |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | 215.412 ms | 108.302 ms | 82.730 ms | 83.839 ms | — | — | 6.606 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 558.786 μs | 286.971 μs | 150.825 μs | 78.160 μs | 450.615 μs | 227.562 μs | 115.182 μs | 60.821 μs | 286.333 μs | 1.935 ms | 1.057 ms | 68.261 μs |
| helmholtz! vec->vec | Float64 128^3 | 5.186 ms | 4.220 ms | 3.854 ms | 3.823 ms | 3.858 ms | 1.986 ms | 1.007 ms | 544.406 μs | 1.802 ms | 5.921 ms | 1.598 ms | 241.633 μs |
| helmholtz! vec->vec | Float64 256^3 | 44.813 ms | 38.769 ms | 36.382 ms | 35.180 ms | 34.872 ms | 20.390 ms | 19.339 ms | 19.560 ms | — | 18.240 ms | 3.879 ms | 1.407 ms |
| helmholtz! vec->vec | Float64 512^3 | — | — | — | — | 252.325 ms | 166.234 ms | 164.485 ms | 166.193 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 593.457 μs | 310.953 μs | 156.789 μs | 86.253 μs | 517.415 μs | 267.393 μs | 130.311 μs | 72.271 μs | 342.613 μs | 2.260 ms | 1.218 ms | 84.050 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 6.146 ms | 3.063 ms | 1.840 ms | 1.618 ms | 6.310 ms | 3.155 ms | 1.593 ms | 804.919 μs | — | — | 1.065 ms | 97.391 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 50.158 ms | 24.608 ms | 20.555 ms | 19.673 ms | 50.192 ms | 25.077 ms | 12.649 ms | 8.523 ms | — | — | 1.706 ms | 626.457 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | — | — | — | — | 401.643 ms | 200.976 ms | 105.731 ms | 83.127 ms | — | — | 7.390 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 779.149 μs | 395.970 μs | 200.974 μs | 106.172 μs | 831.928 μs | 421.624 μs | 211.122 μs | 110.141 μs | — | — | 1.107 ms | 71.080 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 6.666 ms | 4.845 ms | 4.468 ms | 4.407 ms | 6.782 ms | 3.586 ms | 1.739 ms | 919.680 μs | — | — | 1.683 ms | 310.773 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 56.105 ms | 43.079 ms | 40.773 ms | 39.444 ms | 55.724 ms | 28.070 ms | 19.338 ms | 19.384 ms | — | — | 4.462 ms | 1.639 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | — | — | — | — | 436.424 ms | 224.196 ms | 165.166 ms | 165.145 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 817.503 μs | 417.490 μs | 213.933 μs | 113.394 μs | 913.900 μs | 463.495 μs | 225.902 μs | 120.842 μs | — | — | 964.417 μs | 91.661 μs |
| inverse_laplacian! scalar | Float32 128^3 | — | — | — | — | 3.899 ms | 1.323 ms | 668.007 μs | 351.224 μs | — | — | — | 85.901 μs |
| inverse_laplacian! scalar | Float32 256^3 | — | — | — | — | 31.341 ms | 10.621 ms | 5.339 ms | 2.709 ms | — | — | — | 292.763 μs |
| inverse_laplacian! scalar | Float32 512^3 | — | — | — | — | 247.613 ms | 83.675 ms | 41.995 ms | 26.445 ms | — | — | — | — |
| inverse_laplacian! scalar | Float32 64^3 | — | — | — | — | 496.195 μs | 177.162 μs | 92.801 μs | 52.401 μs | — | — | — | 60.001 μs |
| inverse_laplacian! scalar | Float64 128^3 | — | — | — | — | 4.283 ms | 1.424 ms | 720.077 μs | 372.044 μs | — | — | — | 97.071 μs |
| inverse_laplacian! scalar | Float64 256^3 | — | — | — | — | 34.287 ms | 11.491 ms | 5.788 ms | 4.860 ms | — | — | — | 417.504 μs |
| inverse_laplacian! scalar | Float64 512^3 | — | — | — | — | 273.105 ms | 90.660 ms | 54.678 ms | 54.951 ms | — | — | — | — |
| inverse_laplacian! scalar | Float64 64^3 | — | — | — | — | 540.495 μs | 191.581 μs | 100.361 μs | 55.801 μs | — | — | — | 62.401 μs |
| laplacian! scalar | Float32 128^3 | 2.064 ms | 654.294 μs | 335.668 μs | 174.654 μs | 2.146 ms | 492.815 μs | 249.733 μs | 130.752 μs | 265.103 μs | 1.910 ms | 1.181 ms | 79.230 μs |
| laplacian! scalar | Float32 256^3 | 17.204 ms | 6.266 ms | 5.114 ms | 4.573 ms | 17.089 ms | 3.867 ms | 1.939 ms | 1.176 ms | — | 5.490 ms | 1.688 ms | 252.943 μs |
| laplacian! scalar | Float32 512^3 | — | — | — | — | 135.284 ms | 30.703 ms | 27.379 ms | 26.330 ms | — | — | 5.262 ms | — |
| laplacian! scalar | Float32 64^3 | 253.409 μs | 90.201 μs | 49.778 μs | 29.951 μs | 274.063 μs | 68.580 μs | 36.300 μs | 22.200 μs | 83.431 μs | 1.563 ms | 957.239 μs | 52.061 μs |
| laplacian! scalar | Float64 128^3 | 2.151 ms | 818.689 μs | 625.527 μs | 453.410 μs | 2.205 ms | 526.175 μs | 267.003 μs | 140.461 μs | 278.082 μs | 1.957 ms | 1.174 ms | 74.851 μs |
| laplacian! scalar | Float64 256^3 | 17.670 ms | 12.629 ms | 11.985 ms | 11.511 ms | 17.736 ms | 5.148 ms | 4.769 ms | 4.837 ms | — | 4.740 ms | 1.795 ms | 411.554 μs |
| laplacian! scalar | Float64 512^3 | — | — | — | — | 141.483 ms | 53.470 ms | 53.725 ms | 54.965 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 258.431 μs | 94.484 μs | 52.006 μs | 32.627 μs | 281.223 μs | 73.731 μs | 38.740 μs | 23.721 μs | 84.420 μs | 1.586 ms | 1.058 ms | 65.031 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.568 ms | 6.270 ms | 4.679 ms | 4.632 ms | 9.609 ms | 4.871 ms | 2.447 ms | 1.243 ms | — | — | 1.173 ms | 226.842 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 95.270 ms | 51.396 ms | 45.242 ms | 43.393 ms | 80.043 ms | 42.864 ms | 25.285 ms | 25.484 ms | — | — | 2.615 ms | 1.213 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | — | — | — | — | 649.413 ms | 329.518 ms | 208.750 ms | 198.615 ms | — | — | 14.783 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.541 ms | 759.204 μs | 384.861 μs | 200.176 μs | 1.213 ms | 621.856 μs | 310.833 μs | 158.652 μs | — | — | 1.040 ms | 69.811 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 14.266 ms | 11.445 ms | 10.440 ms | 10.391 ms | 10.644 ms | 5.712 ms | 3.769 ms | 3.752 ms | — | — | 1.627 ms | 356.693 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 116.759 ms | 95.790 ms | 88.096 ms | 86.966 ms | 85.169 ms | 52.461 ms | 48.928 ms | 49.421 ms | — | — | 4.370 ms | 2.294 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | — | — | — | — | 692.948 ms | 440.188 ms | 390.425 ms | 398.659 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.606 ms | 785.084 μs | 414.935 μs | 219.733 μs | 1.276 ms | 649.906 μs | 324.984 μs | 166.662 μs | — | — | 1.192 ms | 100.881 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.848 ms | 519.172 μs | 460.198 μs | 358.481 μs | 1.163 μs | 1.175 μs | 1.160 μs | 1.166 μs | 296.642 μs | 1.855 ms | 991.293 μs | 93.901 μs |
| assignment_window | Float32 256^3 | 27.534 ms | 4.133 ms | 5.588 ms | 3.470 ms | 2.217 μs | 2.237 μs | 2.225 μs | 2.227 μs | — | 3.952 ms | 1.684 ms | 93.822 μs |
| assignment_window | Float32 512^3 | — | — | — | — | 4.450 μs | 4.483 μs | 4.476 μs | 4.490 μs | — | — | 5.043 ms | — |
| assignment_window | Float32 64^3 | 240.424 μs | 65.194 μs | 44.367 μs | 38.678 μs | 606.085 ns | 609.949 ns | 606.520 ns | 605.688 ns | 138.651 μs | 1.640 ms | 1.027 ms | 95.041 μs |
| assignment_window | Float64 128^3 | 1.901 ms | 1.011 ms | 820.985 μs | 575.925 μs | 1.582 μs | 1.587 μs | 1.553 μs | 1.572 μs | 306.863 μs | 1.901 ms | 1.136 ms | 92.421 μs |
| assignment_window | Float64 256^3 | 41.039 ms | 8.489 ms | 9.793 ms | 6.226 ms | 3.123 μs | 3.110 μs | 3.113 μs | 3.112 μs | — | 4.237 ms | 1.784 ms | 106.021 μs |
| assignment_window | Float64 512^3 | — | — | — | — | 6.016 μs | 6.042 μs | 5.960 μs | 5.978 μs | — | — | — | — |
| assignment_window | Float64 64^3 | 237.586 μs | 68.329 μs | 65.607 μs | 64.938 μs | 861.754 ns | 825.141 ns | 821.481 ns | 825.190 ns | 141.232 μs | 1.542 ms | 1.162 ms | 89.011 μs |
| combine!∘kernel vector | Float32 128^3 | 4.099 ms | 2.240 ms | 1.715 ms | 1.645 ms | 3.148 ms | 1.547 ms | 774.478 μs | 406.874 μs | — | — | 957.518 μs | 135.661 μs |
| combine!∘kernel vector | Float32 256^3 | 37.490 ms | 22.146 ms | 20.259 ms | 19.790 ms | 25.200 ms | 12.635 ms | 9.904 ms | 9.869 ms | — | — | 1.958 ms | 921.623 μs |
| combine!∘kernel vector | Float32 512^3 | — | — | — | — | 241.726 ms | 101.986 ms | 92.582 ms | 92.954 ms | — | — | 8.534 ms | — |
| combine!∘kernel vector | Float32 64^3 | 494.715 μs | 267.940 μs | 134.409 μs | 75.209 μs | 418.605 μs | 207.312 μs | 106.431 μs | 55.391 μs | — | — | 1.101 ms | 66.600 μs |
| combine!∘kernel vector | Float64 128^3 | 5.648 ms | 4.900 ms | 4.435 ms | 4.427 ms | 3.710 ms | 2.066 ms | 1.098 ms | 746.598 μs | — | — | 1.469 ms | 287.253 μs |
| combine!∘kernel vector | Float64 256^3 | 50.199 ms | 44.417 ms | 40.732 ms | 40.012 ms | 33.977 ms | 23.030 ms | 21.974 ms | 22.132 ms | — | — | 3.008 ms | 1.802 ms |
| combine!∘kernel vector | Float64 512^3 | — | — | — | — | 245.246 ms | 187.574 ms | 182.715 ms | 183.714 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 516.288 μs | 283.545 μs | 142.485 μs | 81.472 μs | 387.474 μs | 228.693 μs | 114.901 μs | 62.821 μs | — | — | 1.001 ms | 83.211 μs |
| convolve! scalar | Float32 128^3 | 1.622 ms | 314.111 μs | 205.492 μs | 87.696 μs | 918.179 μs | 105.701 μs | 54.121 μs | 36.930 μs | 220.032 μs | 1.755 ms | 877.910 μs | 64.391 μs |
| convolve! scalar | Float32 256^3 | 13.663 ms | 8.198 ms | 7.751 ms | 7.123 ms | 7.560 ms | 2.888 ms | 2.671 ms | 2.731 ms | — | 3.659 ms | 1.656 ms | 313.183 μs |
| convolve! scalar | Float32 512^3 | — | — | — | — | 62.068 ms | 37.135 ms | 36.578 ms | 37.187 ms | — | — | 4.192 ms | — |
| convolve! scalar | Float32 64^3 | 202.015 μs | 26.689 μs | 14.629 μs | 11.683 μs | 117.701 μs | 16.250 μs | 9.280 μs | 7.367 μs | 78.951 μs | 1.480 ms | 1.035 ms | 51.760 μs |
| convolve! scalar | Float64 128^3 | 1.847 ms | 1.390 ms | 1.185 ms | 1.117 ms | 998.230 μs | 172.931 μs | 108.721 μs | 72.101 μs | 302.553 μs | 1.784 ms | 1.135 ms | 91.731 μs |
| convolve! scalar | Float64 256^3 | 19.136 ms | 16.911 ms | 16.014 ms | 15.178 ms | 10.978 ms | 7.904 ms | 7.615 ms | 7.743 ms | — | 4.442 ms | 2.019 ms | 578.596 μs |
| convolve! scalar | Float64 512^3 | — | — | — | — | 90.245 ms | 73.494 ms | 73.802 ms | 74.193 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 181.121 μs | 55.189 μs | 26.100 μs | 18.116 μs | 127.311 μs | 26.300 μs | 14.180 μs | 10.430 μs | 78.591 μs | 1.618 ms | 951.395 μs | 57.431 μs |
| convolve! vector | Float32 128^3 | 2.765 ms | 1.925 ms | 1.659 ms | 1.593 ms | 2.101 ms | 1.097 ms | 548.735 μs | 284.543 μs | 731.727 μs | 2.557 ms | 921.484 μs | 108.981 μs |
| convolve! vector | Float32 256^3 | 26.736 ms | 21.677 ms | 20.002 ms | 19.668 ms | 19.630 ms | 10.871 ms | 9.826 ms | 9.863 ms | — | 10.821 ms | 1.185 ms | 687.130 μs |
| convolve! vector | Float32 512^3 | — | — | — | — | 177.794 ms | 93.972 ms | 92.406 ms | 92.729 ms | — | — | 6.065 ms | — |
| convolve! vector | Float32 64^3 | 318.386 μs | 178.979 μs | 90.308 μs | 49.964 μs | 265.933 μs | 146.881 μs | 76.351 μs | 40.300 μs | 161.751 μs | 1.595 ms | 1.094 ms | 69.491 μs |
| convolve! vector | Float64 128^3 | 5.261 ms | 4.843 ms | 4.388 ms | 4.243 ms | 2.605 ms | 1.533 ms | 875.319 μs | 748.228 μs | 792.657 μs | 2.910 ms | 1.329 ms | 227.082 μs |
| convolve! vector | Float64 256^3 | 46.440 ms | 43.366 ms | 40.450 ms | 39.756 ms | 30.569 ms | 22.824 ms | 21.921 ms | 23.336 ms | — | 12.297 ms | 2.365 ms | 1.328 ms |
| convolve! vector | Float64 512^3 | — | — | — | — | 216.391 ms | 186.041 ms | 181.595 ms | 183.369 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 284.305 μs | 169.910 μs | 89.571 μs | 54.907 μs | 221.142 μs | 138.041 μs | 70.731 μs | 40.700 μs | 167.451 μs | 1.655 ms | 1.102 ms | 85.591 μs |
| convolve! vector ∘ radial    | Float32 128^3 | — | — | — | — | 2.501 ms | 1.248 ms | 621.806 μs | 320.224 μs | — | — | — | 136.492 μs |
| convolve! vector ∘ radial    | Float32 256^3 | — | — | — | — | 23.854 ms | 9.943 ms | 8.199 ms | 8.357 ms | — | — | — | 680.220 μs |
| convolve! vector ∘ radial    | Float32 512^3 | — | — | — | — | 163.709 ms | 85.687 ms | 81.600 ms | 82.263 ms | — | — | — | — |
| convolve! vector ∘ radial    | Float32 64^3 | — | — | — | — | 315.994 μs | 160.111 μs | 82.161 μs | 44.670 μs | — | — | — | 61.341 μs |
| convolve! vector ∘ radial    | Float64 128^3 | — | — | — | — | 2.881 ms | 1.456 ms | 725.047 μs | 408.544 μs | — | — | — | 199.642 μs |
| convolve! vector ∘ radial    | Float64 256^3 | — | — | — | — | 23.825 ms | 18.552 ms | 18.737 ms | 19.028 ms | — | — | — | 1.136 ms |
| convolve! vector ∘ radial    | Float64 512^3 | — | — | — | — | 190.450 ms | 162.437 ms | 159.924 ms | 163.249 ms | — | — | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | — | — | — | — | 355.124 μs | 174.721 μs | 89.451 μs | 49.610 μs | — | — | — | 72.201 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | — | — | — | — | 2.096 ms | 1.101 ms | 549.355 μs | 286.123 μs | — | — | — | 108.741 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | — | — | — | — | 19.571 ms | 10.801 ms | 9.825 ms | 9.827 ms | — | — | — | 691.667 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | — | — | — | — | 177.041 ms | 94.239 ms | 92.014 ms | 92.431 ms | — | — | — | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | — | — | — | — | 266.082 μs | 147.112 μs | 76.161 μs | 40.231 μs | — | — | — | 61.040 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | — | — | — | — | 2.623 ms | 1.537 ms | 884.199 μs | 741.488 μs | — | — | — | 229.042 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | — | — | — | — | 30.214 ms | 22.450 ms | 21.913 ms | 23.279 ms | — | — | — | 1.303 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | — | — | — | — | 213.402 ms | 184.492 ms | 181.668 ms | 183.153 ms | — | — | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | — | — | — | — | 220.563 μs | 135.471 μs | 70.301 μs | 40.491 μs | — | — | — | 68.241 μs |
| convolve! vector ∘ separable | Float32 128^3 | — | — | — | — | 4.679 ms | 2.342 ms | 1.170 ms | 595.136 μs | — | — | — | 134.182 μs |
| convolve! vector ∘ separable | Float32 256^3 | — | — | — | — | 37.212 ms | 18.637 ms | 9.368 ms | 8.430 ms | — | — | — | 696.639 μs |
| convolve! vector ∘ separable | Float32 512^3 | — | — | — | — | 296.229 ms | 148.024 ms | 82.468 ms | 82.506 ms | — | — | — | — |
| convolve! vector ∘ separable | Float32 64^3 | — | — | — | — | 588.226 μs | 297.183 μs | 150.231 μs | 77.750 μs | — | — | — | 58.331 μs |
| convolve! vector ∘ separable | Float64 128^3 | — | — | — | — | 3.944 ms | 1.977 ms | 1.002 ms | 508.775 μs | — | — | — | 273.733 μs |
| convolve! vector ∘ separable | Float64 256^3 | — | — | — | — | 32.684 ms | 19.102 ms | 18.945 ms | 19.230 ms | — | — | — | 1.686 ms |
| convolve! vector ∘ separable | Float64 512^3 | — | — | — | — | 261.127 ms | 162.535 ms | 160.190 ms | 163.937 ms | — | — | — | — |
| convolve! vector ∘ separable | Float64 64^3 | — | — | — | — | 494.465 μs | 247.843 μs | 125.981 μs | 66.391 μs | — | — | — | 86.011 μs |
| convolve! vector ∘ stored    | Float32 128^3 | — | — | — | — | 2.101 ms | 1.102 ms | 548.946 μs | 288.073 μs | — | — | — | 102.921 μs |
| convolve! vector ∘ stored    | Float32 256^3 | — | — | — | — | 19.500 ms | 10.879 ms | 9.845 ms | 9.890 ms | — | — | — | 687.529 μs |
| convolve! vector ∘ stored    | Float32 512^3 | — | — | — | — | 177.987 ms | 94.174 ms | 92.411 ms | 92.678 ms | — | — | — | — |
| convolve! vector ∘ stored    | Float32 64^3 | — | — | — | — | 268.863 μs | 147.491 μs | 76.071 μs | 40.430 μs | — | — | — | 65.630 μs |
| convolve! vector ∘ stored    | Float64 128^3 | — | — | — | — | 2.631 ms | 1.548 ms | 890.159 μs | 754.868 μs | — | — | — | 224.422 μs |
| convolve! vector ∘ stored    | Float64 256^3 | — | — | — | — | 30.567 ms | 22.831 ms | 21.923 ms | 22.074 ms | — | — | — | 1.310 ms |
| convolve! vector ∘ stored    | Float64 512^3 | — | — | — | — | 216.348 ms | 186.027 ms | 181.804 ms | 183.330 ms | — | — | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | — | — | — | — | 220.662 μs | 137.231 μs | 71.851 μs | 40.251 μs | — | — | — | 87.921 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.737 ms | 2.434 ms | 1.659 ms | 900.167 μs | 4.991 ms | 2.116 ms | 1.064 ms | 540.806 μs | — | — | 1.058 ms | 70.450 μs |
| exponential_convolve! scalar | Float32 256^3 | 34.376 ms | 13.310 ms | 7.294 ms | 5.716 ms | 39.666 ms | 16.613 ms | 8.306 ms | 4.223 ms | — | — | 1.651 ms | 256.214 μs |
| exponential_convolve! scalar | Float32 512^3 | — | — | — | — | 316.360 ms | 131.459 ms | 67.981 ms | 34.184 ms | — | — | 5.951 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 2.197 ms | 1.065 ms | 569.902 μs | 299.039 μs | 640.356 μs | 279.823 μs | 144.401 μs | 78.171 μs | — | — | 999.111 μs | 57.980 μs |
| exponential_convolve! scalar | Float64 128^3 | 8.249 ms | 3.745 ms | 2.332 ms | 1.452 ms | 5.534 ms | 2.380 ms | 1.196 ms | 612.507 μs | — | — | 1.328 ms | 126.411 μs |
| exponential_convolve! scalar | Float64 256^3 | 55.341 ms | 24.571 ms | 14.316 ms | 11.623 ms | 43.961 ms | 18.803 ms | 9.429 ms | 4.991 ms | — | — | 2.622 ms | 644.777 μs |
| exponential_convolve! scalar | Float64 512^3 | — | — | — | — | 348.563 ms | 149.341 ms | 79.376 ms | 54.935 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 728.857 μs | 327.894 μs | 171.385 μs | 96.734 μs | 694.677 μs | 313.213 μs | 158.272 μs | 86.021 μs | — | — | 986.434 μs | 64.240 μs |
| exponential_convolve! vector | Float32 128^3 | 19.222 ms | 9.091 ms | 5.798 ms | 3.138 ms | 16.520 ms | 7.665 ms | 3.842 ms | 1.959 ms | — | — | 1.208 ms | 137.112 μs |
| exponential_convolve! vector | Float32 256^3 | 116.910 ms | 53.126 ms | 28.672 ms | 18.878 ms | 130.345 ms | 60.344 ms | 30.346 ms | 15.587 ms | — | — | 3.202 ms | 695.507 μs |
| exponential_convolve! vector | Float32 512^3 | — | — | — | — | 1.038 s | 477.842 ms | 241.243 ms | 126.168 ms | — | — | 14.658 ms | — |
| exponential_convolve! vector | Float32 64^3 | 6.916 ms | 3.524 ms | 1.824 ms | 944.164 μs | 2.138 ms | 1.031 ms | 500.135 μs | 261.863 μs | — | — | 1.051 ms | 62.221 μs |
| exponential_convolve! vector | Float64 128^3 | 27.270 ms | 12.988 ms | 7.841 ms | 5.008 ms | 18.438 ms | 8.627 ms | 4.330 ms | 2.204 ms | — | — | 1.842 ms | 287.892 μs |
| exponential_convolve! vector | Float64 256^3 | 184.797 ms | 87.239 ms | 47.961 ms | 35.237 ms | 148.736 ms | 67.971 ms | 34.535 ms | 19.334 ms | — | — | 5.713 ms | 1.773 ms |
| exponential_convolve! vector | Float64 512^3 | — | — | — | — | 1.157 s | 536.451 ms | 272.619 ms | 164.043 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.524 ms | 1.171 ms | 604.600 μs | 321.396 μs | 2.324 ms | 1.091 ms | 552.276 μs | 283.844 μs | — | — | 1.060 ms | 83.771 μs |
| inv separable | Float32 128^3 | — | — | — | — | 773.518 ns | 778.952 ns | 767.890 ns | 759.288 ns | — | — | — | 149.721 μs |
| inv separable | Float32 256^3 | — | — | — | — | 1.549 μs | 1.564 μs | 1.573 μs | 1.560 μs | — | — | — | 154.762 μs |
| inv separable | Float32 512^3 | — | — | — | — | 3.001 μs | 3.025 μs | 3.020 μs | 3.075 μs | — | — | — | — |
| inv separable | Float32 64^3 | — | — | — | — | 411.955 ns | 412.116 ns | 412.719 ns | 408.497 ns | — | — | — | 146.512 μs |
| inv separable | Float64 128^3 | — | — | — | — | 1.057 μs | 1.086 μs | 1.078 μs | 1.051 μs | — | — | — | 149.251 μs |
| inv separable | Float64 256^3 | — | — | — | — | 2.022 μs | 2.053 μs | 2.143 μs | 2.084 μs | — | — | — | 206.633 μs |
| inv separable | Float64 512^3 | — | — | — | — | 3.976 μs | 3.974 μs | 3.986 μs | 4.016 μs | — | — | — | — |
| inv separable | Float64 64^3 | — | — | — | — | 518.696 ns | 525.349 ns | 574.614 ns | 524.979 ns | — | — | — | 149.851 μs |
| materialize_kernel radial | Float32 128^3 | — | — | — | — | 1.129 ms | 351.943 μs | 178.982 μs | 93.851 μs | — | — | — | 94.411 μs |
| materialize_kernel radial | Float32 256^3 | — | — | — | — | 8.904 ms | 2.760 ms | 1.972 ms | 1.824 ms | — | — | — | 217.823 μs |
| materialize_kernel radial | Float32 512^3 | — | — | — | — | 70.810 ms | 22.141 ms | 17.180 ms | 17.528 ms | — | — | — | — |
| materialize_kernel radial | Float32 64^3 | — | — | — | — | 145.601 μs | 47.801 μs | 26.460 μs | 15.700 μs | — | — | — | 71.981 μs |
| materialize_kernel radial | Float64 128^3 | — | — | — | — | 1.174 ms | 380.304 μs | 264.922 μs | 253.083 μs | — | — | — | 89.381 μs |
| materialize_kernel radial | Float64 256^3 | — | — | — | — | 9.313 ms | 4.106 ms | 3.878 ms | 3.859 ms | — | — | — | 255.453 μs |
| materialize_kernel radial | Float64 512^3 | — | — | — | — | 74.489 ms | 91.941 ms | 52.873 ms | 35.766 ms | — | — | — | — |
| materialize_kernel radial | Float64 64^3 | — | — | — | — | 151.121 μs | 48.020 μs | 25.440 μs | 15.910 μs | — | — | — | 76.121 μs |
| materialize_kernel separable | Float32 128^3 | — | — | — | — | 1.533 ms | 445.595 μs | 225.982 μs | 116.912 μs | — | — | — | 78.370 μs |
| materialize_kernel separable | Float32 256^3 | — | — | — | — | 12.126 ms | 3.495 ms | 2.008 ms | 1.788 ms | — | — | — | 231.963 μs |
| materialize_kernel separable | Float32 512^3 | — | — | — | — | 96.549 ms | 27.885 ms | 18.950 ms | 17.906 ms | — | — | — | — |
| materialize_kernel separable | Float32 64^3 | — | — | — | — | 196.132 μs | 60.220 μs | 32.000 μs | 18.761 μs | — | — | — | 70.721 μs |
| materialize_kernel separable | Float64 128^3 | — | — | — | — | 1.447 ms | 456.985 μs | 296.063 μs | 215.432 μs | — | — | — | 113.981 μs |
| materialize_kernel separable | Float64 256^3 | — | — | — | — | 11.432 ms | 4.020 ms | 3.946 ms | 4.021 ms | — | — | — | 415.054 μs |
| materialize_kernel separable | Float64 512^3 | — | — | — | — | 90.986 ms | 104.961 ms | 62.488 ms | 43.728 ms | — | — | — | — |
| materialize_kernel separable | Float64 64^3 | — | — | — | — | 186.292 μs | 61.030 μs | 32.261 μs | 19.281 μs | — | — | — | 73.281 μs |
| radial_kernel | Float32 128^3 | — | — | — | — | 3.200 ns | 3.170 ns | 3.180 ns | 3.050 ns | — | — | — | 1.496 μs |
| radial_kernel | Float32 256^3 | — | — | — | — | 3.180 ns | 3.180 ns | 3.180 ns | 3.050 ns | — | — | — | 1.943 μs |
| radial_kernel | Float32 512^3 | — | — | — | — | 3.190 ns | 3.170 ns | 3.180 ns | 3.050 ns | — | — | — | — |
| radial_kernel | Float32 64^3 | — | — | — | — | 3.200 ns | 3.170 ns | 3.180 ns | 3.040 ns | — | — | — | 2.190 μs |
| radial_kernel | Float64 128^3 | — | — | — | — | 3.200 ns | 3.170 ns | 3.180 ns | 3.170 ns | — | — | — | 2.004 μs |
| radial_kernel | Float64 256^3 | — | — | — | — | 3.200 ns | 3.160 ns | 3.160 ns | 3.150 ns | — | — | — | 1.350 μs |
| radial_kernel | Float64 512^3 | — | — | — | — | 3.190 ns | 3.170 ns | 3.170 ns | 3.170 ns | — | — | — | — |
| radial_kernel | Float64 64^3 | — | — | — | — | 3.200 ns | 3.170 ns | 3.170 ns | 3.150 ns | — | — | — | 1.294 μs |
| spectral_band | Float32 128^3 | 4.252 ms | 1.621 ms | 834.592 μs | 441.121 μs | 9.049 ns | 9.650 ns | 10.420 ns | 8.769 ns | 334.154 μs | 2.050 ms | 1.005 ms | 1.520 μs |
| spectral_band | Float32 256^3 | 46.117 ms | 12.797 ms | 10.084 ms | 5.548 ms | 9.039 ns | 9.670 ns | 10.430 ns | 8.779 ns | — | 6.344 ms | 1.755 ms | 1.469 μs |
| spectral_band | Float32 512^3 | — | — | — | — | 9.039 ns | 9.660 ns | 10.430 ns | 8.769 ns | — | — | 7.315 ms | — |
| spectral_band | Float32 64^3 | 540.920 μs | 216.585 μs | 115.386 μs | 63.530 μs | 9.039 ns | 9.670 ns | 10.421 ns | 8.769 ns | 106.071 μs | 1.537 ms | 1.000 ms | 2.603 μs |
| spectral_band | Float64 128^3 | 4.310 ms | 1.590 ms | 966.909 μs | 624.952 μs | 10.280 ns | 10.080 ns | 10.100 ns | 9.770 ns | 361.113 μs | 2.105 ms | 1.221 ms | 1.339 μs |
| spectral_band | Float64 256^3 | 58.860 ms | 12.495 ms | 13.852 ms | 8.086 ms | 10.260 ns | 10.090 ns | 10.080 ns | 9.770 ns | — | 5.611 ms | 2.014 ms | 2.402 μs |
| spectral_band | Float64 512^3 | — | — | — | — | 10.270 ns | 10.090 ns | 10.100 ns | 9.820 ns | — | — | — | — |
| spectral_band | Float64 64^3 | 530.525 μs | 214.887 μs | 113.729 μs | 71.733 μs | 10.260 ns | 10.090 ns | 10.100 ns | 9.760 ns | 110.411 μs | 1.651 ms | 866.015 μs | 1.780 μs |
| spectral_cutoff | Float32 128^3 | 4.270 ms | 1.655 ms | 839.296 μs | 442.373 μs | 9.069 ns | 10.591 ns | 10.480 ns | 8.959 ns | 331.623 μs | 2.046 ms | 1.093 ms | 1.321 μs |
| spectral_cutoff | Float32 256^3 | 45.919 ms | 12.710 ms | 10.131 ms | 5.435 ms | 9.069 ns | 10.571 ns | 10.501 ns | 8.949 ns | — | 5.403 ms | 1.983 ms | 1.433 μs |
| spectral_cutoff | Float32 512^3 | — | — | — | — | 9.059 ns | 10.601 ns | 10.490 ns | 8.949 ns | — | — | 6.140 ms | — |
| spectral_cutoff | Float32 64^3 | 548.228 μs | 217.012 μs | 114.396 μs | 63.484 μs | 9.059 ns | 10.631 ns | 10.480 ns | 8.949 ns | 108.881 μs | 1.625 ms | 1.105 ms | 2.207 μs |
| spectral_cutoff | Float64 128^3 | 4.261 ms | 1.590 ms | 972.055 μs | 631.094 μs | 9.369 ns | 10.060 ns | 10.200 ns | 9.149 ns | 351.793 μs | 2.120 ms | 1.131 ms | 1.588 μs |
| spectral_cutoff | Float64 256^3 | 59.017 ms | 12.879 ms | 13.948 ms | 8.048 ms | 9.379 ns | 10.060 ns | 10.270 ns | 9.179 ns | — | 5.621 ms | 2.006 ms | 1.566 μs |
| spectral_cutoff | Float64 512^3 | — | — | — | — | 9.360 ns | 10.060 ns | 10.290 ns | 9.179 ns | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 534.876 μs | 213.217 μs | 114.093 μs | 69.801 μs | 9.379 ns | 10.050 ns | 10.260 ns | 9.159 ns | 117.711 μs | 1.647 ms | 1.006 ms | 1.813 μs |
| squared_wavenumber_field | Float32 128^3 | 1.881 ms | 489.911 μs | 448.601 μs | 349.437 μs | — | — | — | — | 262.463 μs | 1.824 ms | 961.813 μs | — |
| squared_wavenumber_field | Float32 256^3 | 27.592 ms | 4.127 ms | 5.585 ms | 3.472 ms | — | — | — | — | — | 3.812 ms | 1.541 ms | — |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | — | — | — | — | — | — | 4.991 ms | — |
| squared_wavenumber_field | Float32 64^3 | 233.436 μs | 63.047 μs | 35.087 μs | 39.058 μs | — | — | — | — | 91.321 μs | 1.517 ms | 954.784 μs | — |
| squared_wavenumber_field | Float64 128^3 | 1.904 ms | 1.001 ms | 818.893 μs | 591.955 μs | — | — | — | — | 264.163 μs | 1.805 ms | 1.079 ms | — |
| squared_wavenumber_field | Float64 256^3 | 41.025 ms | 8.109 ms | 9.821 ms | 6.080 ms | — | — | — | — | — | 4.151 ms | 1.758 ms | — |
| squared_wavenumber_field | Float64 64^3 | 235.679 μs | 63.357 μs | 67.986 μs | 62.943 μs | — | — | — | — | 88.931 μs | 1.612 ms | 1.059 ms | — |
| translation_kernel | Float32 128^3 | 1.839 ms | 787.619 μs | 481.587 μs | 331.665 μs | 1.411 μs | 1.421 μs | 1.418 μs | 1.417 μs | — | — | 1.218 ms | 80.071 μs |
| translation_kernel | Float32 256^3 | 27.554 ms | 6.188 ms | 6.949 ms | 4.066 ms | 2.727 μs | 2.748 μs | 2.728 μs | 2.731 μs | — | — | 1.653 ms | 72.811 μs |
| translation_kernel | Float32 512^3 | — | — | — | — | 5.317 μs | 5.309 μs | 5.290 μs | 5.309 μs | — | — | 5.084 ms | — |
| translation_kernel | Float32 64^3 | 232.583 μs | 105.855 μs | 58.738 μs | 40.614 μs | 740.333 ns | 747.581 ns | 738.728 ns | 742.808 ns | — | — | 1.138 ms | 74.390 μs |
| translation_kernel | Float64 128^3 | 1.827 ms | 1.003 ms | 769.033 μs | 536.206 μs | 1.846 μs | 1.854 μs | 1.836 μs | 1.818 μs | — | — | 1.338 ms | 78.341 μs |
| translation_kernel | Float64 256^3 | 41.093 ms | 8.494 ms | 10.708 ms | 6.716 ms | 3.481 μs | 3.501 μs | 3.501 μs | 3.489 μs | — | — | 2.213 ms | 90.141 μs |
| translation_kernel | Float64 512^3 | — | — | — | — | 6.897 μs | 6.880 μs | 6.800 μs | 6.820 μs | — | — | — | — |
| translation_kernel | Float64 64^3 | 231.216 μs | 101.023 μs | 74.401 μs | 60.787 μs | 940.357 ns | 941.667 ns | 930.032 ns | 933.483 ns | — | — | 1.188 ms | 81.460 μs |
| translation_kernel! | Float32 128^3 | — | — | — | — | 1.387 μs | 1.367 μs | 1.369 μs | 1.367 μs | — | — | — | 62.370 μs |
| translation_kernel! | Float32 256^3 | — | — | — | — | 2.612 μs | 2.616 μs | 2.616 μs | 2.611 μs | — | — | — | 62.881 μs |
| translation_kernel! | Float32 512^3 | — | — | — | — | 5.117 μs | 5.117 μs | 5.108 μs | 5.110 μs | — | — | — | — |
| translation_kernel! | Float32 64^3 | — | — | — | — | 698.618 ns | 700.979 ns | 699.382 ns | 699.731 ns | — | — | — | 73.941 μs |
| translation_kernel! | Float64 128^3 | — | — | — | — | 1.702 μs | 1.697 μs | 1.698 μs | 1.698 μs | — | — | — | 67.221 μs |
| translation_kernel! | Float64 256^3 | — | — | — | — | 3.265 μs | 3.244 μs | 3.243 μs | 3.259 μs | — | — | — | 72.810 μs |
| translation_kernel! | Float64 512^3 | — | — | — | — | 6.416 μs | 6.352 μs | 6.358 μs | 6.428 μs | — | — | — | — |
| translation_kernel! | Float64 64^3 | — | — | — | — | 882.308 ns | 880.196 ns | 878.113 ns | 877.222 ns | — | — | — | 63.141 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 28.888 ms | 13.922 ms | 7.765 ms | 4.633 ms | 20.912 ms | 11.048 ms | 5.914 ms | 3.413 ms | 2.280 ms | 4.864 ms | 1.343 ms | 211.552 μs |
| anterpolate! CatmullRom | Float32 256^3 | 436.132 ms | 225.143 ms | 120.356 ms | 75.195 ms | 175.213 ms | 89.919 ms | 45.737 ms | 23.771 ms | — | 17.932 ms | 4.044 ms | 2.905 ms |
| anterpolate! CatmullRom | Float32 512^3 | — | — | — | — | 2.986 s | 1.528 s | 788.684 ms | 435.002 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.238 ms | 1.913 ms | 1.248 ms | 938.078 μs | 2.513 ms | 1.459 ms | 942.559 μs | 654.158 μs | 116.972 μs | 2.057 ms | 1.220 ms | 103.811 μs |
| anterpolate! CatmullRom | Float64 128^3 | 34.657 ms | 16.258 ms | 8.125 ms | 4.852 ms | 22.054 ms | 11.577 ms | 6.134 ms | 3.552 ms | 2.691 ms | 4.862 ms | 1.628 ms | 232.732 μs |
| anterpolate! CatmullRom | Float64 256^3 | 546.414 ms | 287.805 ms | 165.743 ms | 114.407 ms | 263.718 ms | 130.823 ms | 68.642 ms | 35.866 ms | — | 19.810 ms | 4.795 ms | 4.674 ms |
| anterpolate! CatmullRom | Float64 512^3 | — | — | — | — | 3.469 s | 1.771 s | 959.186 ms | 533.733 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.389 ms | 1.879 ms | 1.262 ms | 943.395 μs | 2.529 ms | 1.497 ms | 964.220 μs | 694.778 μs | 185.312 μs | 2.004 ms | 1.201 ms | 125.271 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 206.898 ms | 102.438 ms | 54.108 ms | 29.977 ms | 159.823 ms | 80.435 ms | 40.794 ms | 21.754 ms | 12.241 ms | 15.478 ms | 4.182 ms | 1.008 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.398 s | 1.309 s | 748.243 ms | 530.262 ms | 1.285 s | 644.944 ms | 322.793 ms | 162.049 ms | — | 48.567 ms | 18.203 ms | 15.005 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 11.781 s | 6.014 s | 3.044 s | 1.640 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.505 ms | 13.324 ms | 8.405 ms | 5.731 ms | 19.845 ms | 10.595 ms | 6.439 ms | 4.332 ms | 486.825 μs | 5.959 ms | 2.191 ms | 331.873 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 229.887 ms | 111.011 ms | 56.260 ms | 31.446 ms | 160.375 ms | 80.608 ms | 40.553 ms | 21.610 ms | 13.808 ms | 16.564 ms | 4.883 ms | 1.167 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.816 s | 1.516 s | 925.966 ms | 682.498 ms | 1.397 s | 701.875 ms | 355.192 ms | 179.393 ms | — | 66.043 ms | 28.833 ms | 24.277 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 12.935 s | 6.567 s | 3.444 s | 2.239 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 25.148 ms | 13.373 ms | 8.536 ms | 5.942 ms | 19.908 ms | 10.742 ms | 6.589 ms | 4.422 ms | 825.268 μs | 5.503 ms | 2.720 ms | 341.853 μs |
| anterpolate! NUFFT | Float32 128^3 | 440.339 ms | 240.566 ms | 162.121 ms | 126.581 ms | 354.912 ms | 179.100 ms | 99.144 ms | 70.032 ms | 20.177 ms | 18.762 ms | 5.604 ms | 2.807 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.637 s | 2.564 s | 1.595 s | 1.215 s | 3.775 s | 1.865 s | 1.115 s | 600.033 ms | — | 120.799 ms | 32.967 ms | 28.629 ms |
| anterpolate! NUFFT | Float32 512^3 | — | — | — | — | 31.266 s | 16.422 s | 9.091 s | 5.565 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 33.293 ms | 18.266 ms | 11.751 ms | 8.822 ms | 27.034 ms | 14.278 ms | 8.606 ms | 5.963 ms | 1.989 ms | 6.296 ms | 2.380 ms | 448.185 μs |
| anterpolate! NUFFT | Float64 128^3 | 581.682 ms | 329.204 ms | 231.408 ms | 191.318 ms | 424.117 ms | 240.202 ms | 124.203 ms | 90.491 ms | 30.358 ms | 22.503 ms | 10.016 ms | 6.578 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.457 s | 3.104 s | 2.052 s | 1.678 s | 3.631 s | 2.049 s | 1.237 s | 885.952 ms | — | 160.735 ms | 70.065 ms | 58.701 ms |
| anterpolate! NUFFT | Float64 512^3 | — | — | — | — | 40.189 s | 22.106 s | 12.844 s | 8.349 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 40.161 ms | 22.518 ms | 15.032 ms | 11.464 ms | 33.229 ms | 17.929 ms | 10.768 ms | 7.422 ms | 3.892 ms | 8.203 ms | 3.612 ms | 844.939 μs |
| anterpolate! trilinear | Float32 128^3 | 4.520 ms | 2.277 ms | 1.400 ms | 963.981 μs | 4.768 ms | 2.531 ms | 1.436 ms | 861.569 μs | 460.884 μs | 2.018 ms | 990.949 μs | 77.391 μs |
| anterpolate! trilinear | Float32 256^3 | 89.673 ms | 48.898 ms | 28.408 ms | 21.164 ms | 42.961 ms | 22.643 ms | 11.942 ms | 6.548 ms | — | 6.631 ms | 1.780 ms | 740.780 μs |
| anterpolate! trilinear | Float32 512^3 | — | — | — | — | 752.687 ms | 401.125 ms | 205.681 ms | 120.364 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 491.280 μs | 331.491 μs | 225.859 μs | 179.253 μs | 369.244 μs | 228.092 μs | 167.742 μs | 127.042 μs | 70.080 μs | 1.565 ms | 1.061 ms | 66.331 μs |
| anterpolate! trilinear | Float64 128^3 | 5.640 ms | 2.855 ms | 1.720 ms | 1.321 ms | 5.987 ms | 3.404 ms | 1.871 ms | 1.171 ms | 596.666 μs | 1.980 ms | 1.202 ms | 95.391 μs |
| anterpolate! trilinear | Float64 256^3 | 97.343 ms | 55.716 ms | 36.209 ms | 29.492 ms | 72.130 ms | 36.849 ms | 19.998 ms | 11.359 ms | — | 6.838 ms | 1.761 ms | 1.121 ms |
| anterpolate! trilinear | Float64 512^3 | — | — | — | — | 797.636 ms | 405.638 ms | 228.511 ms | 129.219 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 523.595 μs | 343.748 μs | 259.583 μs | 210.906 μs | 381.854 μs | 238.882 μs | 178.662 μs | 133.821 μs | 83.721 μs | 1.554 ms | 936.908 μs | 75.531 μs |
| interpolate! CatmullRom | Float32 128^3 | 12.564 ms | 6.150 ms | 3.087 ms | 1.711 ms | 5.425 ms | 2.762 ms | 1.392 ms | 738.058 μs | 972.889 μs | 3.140 ms | 1.376 ms | 127.071 μs |
| interpolate! CatmullRom | Float32 256^3 | 298.273 ms | 156.282 ms | 82.104 ms | 53.577 ms | 56.253 ms | 29.997 ms | 14.577 ms | 7.106 ms | — | 14.577 ms | 2.785 ms | 877.042 μs |
| interpolate! CatmullRom | Float32 512^3 | — | — | — | — | 1.864 s | 955.565 ms | 471.362 ms | 262.337 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.333 ms | 715.329 μs | 437.043 μs | 299.843 μs | 615.876 μs | 331.993 μs | 199.181 μs | 135.851 μs | 101.321 μs | 1.724 ms | 1.188 ms | 79.591 μs |
| interpolate! CatmullRom | Float64 128^3 | 17.215 ms | 7.511 ms | 3.790 ms | 1.989 ms | 5.656 ms | 2.871 ms | 1.443 ms | 771.479 μs | 1.411 ms | 2.789 ms | 1.410 ms | 188.842 μs |
| interpolate! CatmullRom | Float64 256^3 | 326.167 ms | 167.984 ms | 98.558 ms | 65.427 ms | 151.427 ms | 71.177 ms | 37.894 ms | 19.384 ms | — | 12.939 ms | 2.854 ms | 1.709 ms |
| interpolate! CatmullRom | Float64 512^3 | — | — | — | — | 2.133 s | 1.059 s | 564.553 ms | 306.763 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.418 ms | 755.274 μs | 460.251 μs | 320.814 μs | 664.747 μs | 354.734 μs | 216.343 μs | 144.432 μs | 166.201 μs | 1.759 ms | 1.283 ms | 115.651 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 77.824 ms | 39.254 ms | 19.789 ms | 10.830 ms | 42.292 ms | 21.290 ms | 10.688 ms | 5.675 ms | 5.370 ms | 14.027 ms | 3.038 ms | 480.305 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.545 s | 885.882 ms | 541.871 ms | 353.399 ms | 347.967 ms | 179.280 ms | 88.337 ms | 44.311 ms | — | 30.216 ms | 11.603 ms | 4.720 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 5.375 s | 2.949 s | 1.541 s | 875.888 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.922 ms | 4.742 ms | 2.891 ms | 1.939 ms | 5.069 ms | 2.674 ms | 1.607 ms | 1.079 ms | 688.416 μs | 3.166 ms | 1.783 ms | 276.323 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 99.290 ms | 48.176 ms | 24.054 ms | 13.184 ms | 41.761 ms | 20.951 ms | 10.497 ms | 5.527 ms | 8.105 ms | 9.517 ms | 2.980 ms | 834.399 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.989 s | 1.100 s | 707.401 ms | 470.630 ms | 584.489 ms | 287.259 ms | 149.874 ms | 75.836 ms | — | 28.103 ms | 10.932 ms | 10.043 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 6.976 s | 3.593 s | 1.967 s | 1.187 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.195 ms | 4.828 ms | 2.989 ms | 2.017 ms | 5.255 ms | 2.784 ms | 1.677 ms | 1.116 ms | 911.428 μs | 3.595 ms | 2.314 ms | 336.803 μs |
| interpolate! NUFFT | Float32 128^3 | 343.312 ms | 196.862 ms | 143.368 ms | 99.919 ms | 239.450 ms | 127.640 ms | 72.959 ms | 45.847 ms | 12.723 ms | 16.422 ms | 4.893 ms | 1.904 ms |
| interpolate! NUFFT | Float32 256^3 | 3.806 s | 2.221 s | 1.451 s | 1.054 s | 2.992 s | 1.551 s | 866.222 ms | 529.164 ms | — | 72.243 ms | 26.214 ms | 17.658 ms |
| interpolate! NUFFT | Float32 512^3 | — | — | — | — | 24.896 s | 13.356 s | 7.715 s | 4.977 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 17.897 ms | 10.623 ms | 7.107 ms | 5.480 ms | 11.956 ms | 6.428 ms | 3.801 ms | 2.451 ms | 1.847 ms | 4.302 ms | 2.275 ms | 429.055 μs |
| interpolate! NUFFT | Float64 128^3 | 456.351 ms | 275.340 ms | 209.942 ms | 177.430 ms | 226.096 ms | 139.544 ms | 81.550 ms | 77.002 ms | 25.361 ms | 18.237 ms | 8.627 ms | 5.546 ms |
| interpolate! NUFFT | Float64 256^3 | 4.178 s | 2.527 s | 1.822 s | 1.457 s | 2.045 s | 1.258 s | 883.347 ms | 727.957 ms | — | 118.516 ms | 56.632 ms | 47.626 ms |
| interpolate! NUFFT | Float64 512^3 | — | — | — | — | 25.049 s | 14.272 s | 8.837 s | 9.494 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 24.681 ms | 15.168 ms | 11.037 ms | 9.321 ms | 17.750 ms | 9.778 ms | 5.963 ms | 4.100 ms | 3.417 ms | 6.116 ms | 3.003 ms | 946.980 μs |
| interpolate! trilinear | Float32 128^3 | 2.040 ms | 1.064 ms | 548.762 μs | 298.410 μs | 1.327 ms | 663.706 μs | 335.743 μs | 179.412 μs | 255.582 μs | 1.719 ms | 1.094 ms | 66.201 μs |
| interpolate! trilinear | Float32 256^3 | 58.965 ms | 31.153 ms | 16.962 ms | 9.612 ms | 14.416 ms | 7.774 ms | 3.689 ms | 1.844 ms | — | 3.594 ms | 1.280 ms | 253.583 μs |
| interpolate! trilinear | Float32 512^3 | — | — | — | — | 436.733 ms | 248.707 ms | 120.209 ms | 63.383 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 229.927 μs | 130.069 μs | 79.441 μs | 55.421 μs | 146.781 μs | 79.010 μs | 47.651 μs | 33.231 μs | 65.160 μs | 1.448 ms | 957.585 μs | 59.670 μs |
| interpolate! trilinear | Float64 128^3 | 2.701 ms | 1.303 ms | 684.250 μs | 376.231 μs | 1.348 ms | 691.856 μs | 351.624 μs | 188.992 μs | 325.503 μs | 1.772 ms | 1.092 ms | 84.371 μs |
| interpolate! trilinear | Float64 256^3 | 63.559 ms | 34.975 ms | 21.773 ms | 14.148 ms | 33.564 ms | 16.440 ms | 8.292 ms | 4.185 ms | — | 4.014 ms | 1.595 ms | 417.505 μs |
| interpolate! trilinear | Float64 512^3 | — | — | — | — | 451.533 ms | 227.685 ms | 129.156 ms | 65.104 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 243.070 μs | 135.937 μs | 83.635 μs | 59.224 μs | 162.421 μs | 86.470 μs | 50.161 μs | 33.570 μs | 65.930 μs | 1.530 ms | 1.083 ms | 62.471 μs |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.254 ms | 7.184 ms | 7.518 ms | 8.042 ms | 6.958 ms | 4.938 ms | 6.016 ms | 6.042 ms | 2.099 ms | 27.761 ms | 1.656 ms | 320.423 μs |
| co-spectrum vec.vec | Float32 256^3 | 67.299 ms | 48.661 ms | 44.719 ms | 41.361 ms | 55.721 ms | 36.952 ms | 33.381 ms | 29.625 ms | — | 97.666 ms | 3.211 ms | 957.282 μs |
| co-spectrum vec.vec | Float32 512^3 | — | — | — | — | 440.861 ms | 271.900 ms | 192.738 ms | 152.078 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.066 ms | 1.312 ms | 1.499 ms | 1.608 ms | 905.370 μs | 937.409 μs | 1.263 ms | 1.340 ms | 491.824 μs | 17.761 ms | 1.383 ms | 178.142 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.657 ms | 6.773 ms | 6.126 ms | 5.353 ms | 7.259 ms | 5.192 ms | 4.525 ms | 4.756 ms | 2.194 ms | 29.708 ms | 29.468 ms | 400.374 μs |
| co-spectrum vec.vec | Float64 256^3 | 69.632 ms | 48.804 ms | 36.231 ms | 30.082 ms | 58.750 ms | 38.055 ms | 27.222 ms | 23.641 ms | — | 109.563 ms | 66.321 ms | 1.283 ms |
| co-spectrum vec.vec | Float64 512^3 | — | — | — | — | 477.002 ms | 293.798 ms | 177.172 ms | 132.471 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.085 ms | 825.029 μs | 980.776 μs | 1.003 ms | 946.920 μs | 782.498 μs | 856.229 μs | 964.611 μs | 482.135 μs | 16.075 ms | 16.001 ms | 189.722 μs |
| cov vector | Float32 128^3 | — | — | — | — | 1.130 ms | 578.715 μs | 309.064 μs | 177.902 μs | — | — | — | 237.962 μs |
| cov vector | Float32 256^3 | — | — | — | — | 12.210 ms | 8.008 ms | 5.154 ms | 4.641 ms | — | — | — | 949.682 μs |
| cov vector | Float32 512^3 | — | — | — | — | 93.027 ms | 64.637 ms | 55.246 ms | 55.327 ms | — | — | — | — |
| cov vector | Float32 64^3 | — | — | — | — | 144.571 μs | 80.271 μs | 45.690 μs | 37.131 μs | — | — | — | 181.702 μs |
| cov vector | Float64 128^3 | — | — | — | — | 2.218 ms | 1.121 ms | 572.076 μs | 328.614 μs | — | — | — | 367.174 μs |
| cov vector | Float64 256^3 | — | — | — | — | 25.108 ms | 15.006 ms | 12.475 ms | 12.556 ms | — | — | — | 1.520 ms |
| cov vector | Float64 512^3 | — | — | — | — | 186.783 ms | 129.433 ms | 111.115 ms | 111.476 ms | — | — | — | — |
| cov vector | Float64 64^3 | — | — | — | — | 272.233 μs | 145.701 μs | 80.661 μs | 54.691 μs | — | — | — | 197.582 μs |
| cross-correlation vec.vec | Float32 128^3 | 39.547 ms | 34.663 ms | 36.194 ms | 38.616 ms | 33.089 ms | 24.582 ms | 21.935 ms | 21.250 ms | 5.891 ms | 43.640 ms | 2.622 ms | 689.017 μs |
| cross-correlation vec.vec | Float32 256^3 | 474.252 ms | 310.305 ms | 279.929 ms | 270.474 ms | 401.562 ms | 274.237 ms | 203.810 ms | 176.983 ms | — | 186.915 ms | 10.470 ms | 5.839 ms |
| cross-correlation vec.vec | Float32 512^3 | — | — | — | — | 2.919 s | 2.052 s | 1.380 s | 1.186 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.749 ms | 5.378 ms | 6.182 ms | 6.182 ms | 3.875 ms | 3.581 ms | 3.781 ms | 3.704 ms | 1.025 ms | 20.682 ms | 1.467 ms | 273.133 μs |
| cross-correlation vec.vec | Float64 128^3 | 62.493 ms | 61.925 ms | 56.674 ms | 51.020 ms | 47.098 ms | 37.457 ms | 33.804 ms | 31.617 ms | 9.144 ms | 52.055 ms | 51.351 ms | 2.096 ms |
| cross-correlation vec.vec | Float64 256^3 | 694.984 ms | 487.096 ms | 402.316 ms | 373.900 ms | 576.033 ms | 392.788 ms | 295.324 ms | 222.234 ms | — | 217.471 ms | 137.382 ms | 15.013 ms |
| cross-correlation vec.vec | Float64 512^3 | — | — | — | — | 4.618 s | 2.971 s | 2.109 s | 1.793 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.865 ms | 5.997 ms | 5.802 ms | 6.028 ms | 4.213 ms | 3.555 ms | 3.455 ms | 3.310 ms | 1.557 ms | 20.881 ms | 23.884 ms | 323.123 μs |
| inner spectral | Float32 128^3 | 2.563 ms | 1.791 ms | 1.452 ms | 1.334 ms | 1.427 ms | 809.278 μs | 506.145 μs | 363.494 μs | 669.926 μs | 2.049 ms | 1.209 ms | 237.512 μs |
| inner spectral | Float32 256^3 | 23.278 ms | 18.210 ms | 16.587 ms | 15.600 ms | 12.813 ms | 7.724 ms | 7.099 ms | 7.136 ms | — | 3.999 ms | 1.750 ms | 744.770 μs |
| inner spectral | Float32 512^3 | — | — | — | — | 104.735 ms | 77.564 ms | 70.268 ms | 70.246 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 311.019 μs | 205.978 μs | 149.325 μs | 120.701 μs | 206.762 μs | 122.022 μs | 81.951 μs | 74.161 μs | 275.972 μs | 1.780 ms | 1.135 ms | 207.142 μs |
| inner spectral | Float64 128^3 | 4.413 ms | 3.674 ms | 3.246 ms | 3.123 ms | 1.863 ms | 1.094 ms | 732.648 μs | 620.996 μs | 811.337 μs | 2.410 ms | 1.363 ms | 344.324 μs |
| inner spectral | Float64 256^3 | 38.299 ms | 32.438 ms | 29.665 ms | 28.720 ms | 18.333 ms | 15.961 ms | 15.949 ms | 14.944 ms | — | 7.953 ms | 2.789 ms | 1.236 ms |
| inner spectral | Float64 512^3 | — | — | — | — | 127.745 ms | 125.457 ms | 124.319 ms | 125.474 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 320.843 μs | 216.120 μs | 156.316 μs | 128.354 μs | 222.282 μs | 137.651 μs | 88.260 μs | 78.030 μs | 293.003 μs | 1.765 ms | 1.138 ms | 196.812 μs |
| inner vec.vec | Float32 128^3 | 1.342 ms | 990.184 μs | 839.085 μs | 784.529 μs | 377.544 μs | 193.112 μs | 101.822 μs | 73.491 μs | 308.353 μs | 1.623 ms | 794.094 μs | 115.851 μs |
| inner vec.vec | Float32 256^3 | 14.293 ms | 12.958 ms | 12.083 ms | 11.385 ms | 6.829 ms | 6.018 ms | 5.755 ms | 5.897 ms | — | 3.382 ms | 1.298 ms | 572.848 μs |
| inner vec.vec | Float32 512^3 | — | — | — | — | 61.151 ms | 56.569 ms | 55.403 ms | 55.867 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 70.561 μs | 40.413 μs | 21.692 μs | 15.246 μs | 45.930 μs | 25.940 μs | 14.820 μs | 10.090 μs | 98.731 μs | 1.278 ms | 774.243 μs | 89.681 μs |
| inner vec.vec | Float64 128^3 | 3.170 ms | 2.654 ms | 2.422 ms | 2.283 ms | 1.117 ms | 575.026 μs | 360.634 μs | 263.053 μs | 552.615 μs | 1.860 ms | 998.015 μs | 254.533 μs |
| inner vec.vec | Float64 256^3 | 27.690 ms | 25.846 ms | 24.166 ms | 22.893 ms | 15.858 ms | 14.227 ms | 13.217 ms | 13.329 ms | — | 5.634 ms | 2.038 ms | 1.070 ms |
| inner vec.vec | Float64 512^3 | — | — | — | — | 125.374 ms | 112.648 ms | 111.518 ms | 112.181 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 140.726 μs | 79.148 μs | 42.532 μs | 26.139 μs | 87.211 μs | 46.770 μs | 26.170 μs | 17.970 μs | 162.792 μs | 1.434 ms | 777.319 μs | 100.981 μs |
| integral scalar | Float32 128^3 | 111.663 μs | 62.237 μs | 31.233 μs | 20.314 μs | 61.830 μs | 38.640 μs | 20.230 μs | 12.961 μs | 228.932 μs | 1.318 ms | 1.144 ms | 91.911 μs |
| integral scalar | Float32 256^3 | 2.158 ms | 1.576 ms | 1.356 ms | 1.256 ms | 585.106 μs | 302.284 μs | 159.302 μs | 94.991 μs | — | 9.002 ms | 2.302 ms | 251.814 μs |
| integral scalar | Float32 512^3 | — | — | — | — | 11.765 ms | 9.151 ms | 8.872 ms | 9.104 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 9.716 μs | 6.790 μs | 5.853 μs | 6.149 μs | 6.860 μs | 4.810 μs | 4.269 μs | 5.200 μs | 95.301 μs | 1.534 ms | 899.409 μs | 85.131 μs |
| integral scalar | Float64 128^3 | 237.317 μs | 131.226 μs | 68.405 μs | 39.071 μs | 123.651 μs | 62.481 μs | 36.421 μs | 23.830 μs | 221.812 μs | 2.553 ms | 1.192 ms | 106.181 μs |
| integral scalar | Float64 256^3 | 4.624 ms | 3.807 ms | 3.490 ms | 3.241 ms | 2.002 ms | 1.024 ms | 866.869 μs | 944.660 μs | — | 10.817 ms | 2.694 ms | 268.463 μs |
| integral scalar | Float64 512^3 | — | — | — | — | 20.747 ms | 18.825 ms | 17.860 ms | 18.059 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.823 μs | 13.214 μs | 8.356 μs | 8.211 μs | 15.791 μs | 7.481 μs | 5.935 μs | 5.583 μs | 95.391 μs | 1.583 ms | 853.383 μs | 78.711 μs |
| integral spectral vec | Float32 128^3 | 73.574 ns | 68.827 ns | 68.706 ns | 69.278 ns | 68.238 ns | 70.052 ns | 68.402 ns | 68.248 ns | — | — | 847.189 μs | 50.071 μs |
| integral spectral vec | Float32 256^3 | 73.413 ns | 68.980 ns | 69.976 ns | 69.051 ns | 68.956 ns | 70.666 ns | 69.263 ns | 68.401 ns | — | — | 812.731 μs | 47.821 μs |
| integral spectral vec | Float32 512^3 | — | — | — | — | 69.079 ns | 73.300 ns | 72.506 ns | 69.048 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 72.717 ns | 71.669 ns | 68.260 ns | 68.346 ns | 68.261 ns | 69.591 ns | 67.930 ns | 68.167 ns | — | — | 833.215 μs | 57.460 μs |
| integral spectral vec | Float64 128^3 | 75.348 ns | 70.247 ns | 71.222 ns | 70.787 ns | 71.460 ns | 75.201 ns | 75.208 ns | 76.098 ns | — | — | 832.384 μs | 53.450 μs |
| integral spectral vec | Float64 256^3 | 76.678 ns | 71.125 ns | 71.996 ns | 72.808 ns | 72.191 ns | 78.151 ns | 76.447 ns | 76.541 ns | — | — | 808.714 μs | 47.990 μs |
| integral spectral vec | Float64 512^3 | — | — | — | — | 74.430 ns | 80.617 ns | 80.837 ns | 81.290 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 72.326 ns | 69.628 ns | 69.560 ns | 70.826 ns | 75.332 ns | 77.091 ns | 74.401 ns | 77.265 ns | — | — | 842.906 μs | 46.500 μs |
| l2norm vec | Float32 128^3 | 640.793 μs | 338.018 μs | 186.032 μs | 92.844 μs | 240.453 μs | 129.021 μs | 67.541 μs | 39.771 μs | 196.632 μs | 1.582 ms | 854.011 μs | 99.141 μs |
| l2norm vec | Float32 256^3 | 8.328 ms | 6.167 ms | 5.599 ms | 5.442 ms | 4.061 ms | 2.854 ms | 1.979 ms | 1.994 ms | — | 3.219 ms | 1.301 ms | 337.534 μs |
| l2norm vec | Float32 512^3 | — | — | — | — | 39.855 ms | 30.163 ms | 26.835 ms | 27.028 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 50.794 μs | 27.610 μs | 15.886 μs | 11.830 μs | 32.651 μs | 17.400 μs | 9.700 μs | 7.230 μs | 85.641 μs | 1.361 ms | 756.839 μs | 90.451 μs |
| l2norm vec | Float64 128^3 | 1.712 ms | 1.077 ms | 827.080 μs | 779.411 μs | 559.425 μs | 236.442 μs | 127.902 μs | 83.371 μs | 344.333 μs | 1.876 ms | 978.559 μs | 149.041 μs |
| l2norm vec | Float64 256^3 | 15.793 ms | 12.600 ms | 11.618 ms | 11.037 ms | 12.023 ms | 6.503 ms | 5.658 ms | 5.589 ms | — | 5.670 ms | 1.957 ms | 607.376 μs |
| l2norm vec | Float64 512^3 | — | — | — | — | 85.581 ms | 62.266 ms | 54.677 ms | 54.762 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 94.189 μs | 53.113 μs | 28.482 μs | 18.489 μs | 55.050 μs | 29.200 μs | 16.920 μs | 11.031 μs | 134.871 μs | 1.402 ms | 773.034 μs | 106.782 μs |
| lpnorm vec Inf | Float32 128^3 | 1.389 ms | 1.370 ms | 1.146 ms | 1.040 ms | 460.094 μs | 386.324 μs | 342.394 μs | 320.343 μs | 592.145 μs | 3.080 ms | 1.319 ms | 132.462 μs |
| lpnorm vec Inf | Float32 256^3 | 22.791 ms | 14.822 ms | 12.193 ms | 11.084 ms | 7.892 ms | 7.677 ms | 7.971 ms | 7.951 ms | — | 13.216 ms | 3.421 ms | 588.647 μs |
| lpnorm vec Inf | Float32 512^3 | — | — | — | — | 78.662 ms | 91.817 ms | 75.786 ms | 70.509 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 98.887 μs | 92.210 μs | 73.501 μs | 78.929 μs | 62.201 μs | 49.281 μs | 41.430 μs | 42.801 μs | 155.751 μs | 1.641 ms | 964.230 μs | 117.821 μs |
| lpnorm vec Inf | Float64 128^3 | 3.310 ms | 3.191 ms | 2.602 ms | 2.600 ms | 1.176 ms | 1.104 ms | 950.840 μs | 1.004 ms | 660.476 μs | 3.883 ms | 1.668 ms | 249.663 μs |
| lpnorm vec Inf | Float64 256^3 | 47.266 ms | 31.386 ms | 24.155 ms | 22.468 ms | 16.833 ms | 15.997 ms | 16.084 ms | 15.901 ms | — | 14.730 ms | 5.382 ms | 976.950 μs |
| lpnorm vec Inf | Float64 512^3 | — | — | — | — | 148.753 ms | 167.285 ms | 141.274 ms | 139.258 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 238.281 μs | 179.555 μs | 154.396 μs | 145.295 μs | 111.682 μs | 93.541 μs | 76.770 μs | 72.551 μs | 166.092 μs | 1.711 ms | 1.005 ms | 117.481 μs |
| maximum scalar | Float32 128^3 | 345.259 μs | 177.509 μs | 92.029 μs | 51.200 μs | 237.443 μs | 120.201 μs | 60.991 μs | 33.130 μs | 223.322 μs | 2.331 ms | 1.146 ms | 93.121 μs |
| maximum scalar | Float32 256^3 | 2.903 ms | 1.818 ms | 1.454 ms | 1.335 ms | 2.005 ms | 967.221 μs | 482.975 μs | 247.103 μs | — | 9.121 ms | 2.319 ms | 246.133 μs |
| maximum scalar | Float32 512^3 | — | — | — | — | 31.718 ms | 14.344 ms | 9.074 ms | 8.171 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 43.017 μs | 24.700 μs | 14.813 μs | 11.942 μs | 29.401 μs | 15.830 μs | 9.330 μs | 6.600 μs | 101.731 μs | 1.564 ms | 922.422 μs | 88.571 μs |
| maximum scalar | Float64 128^3 | 547.286 μs | 291.499 μs | 144.142 μs | 79.381 μs | 447.755 μs | 221.782 μs | 113.391 μs | 59.420 μs | 244.072 μs | 2.772 ms | 1.301 ms | 117.222 μs |
| maximum scalar | Float64 256^3 | 6.082 ms | 4.302 ms | 3.627 ms | 3.355 ms | 3.973 ms | 2.010 ms | 1.106 ms | 801.808 μs | — | 12.659 ms | 3.329 ms | 292.243 μs |
| maximum scalar | Float64 512^3 | — | — | — | — | 44.626 ms | 27.121 ms | 18.977 ms | 17.462 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 66.519 μs | 37.472 μs | 20.447 μs | 14.675 μs | 55.500 μs | 28.481 μs | 16.030 μs | 10.100 μs | 99.451 μs | 1.634 ms | 947.833 μs | 85.131 μs |
| maximum(norm) vec | Float32 128^3 | 1.840 ms | 927.308 μs | 474.221 μs | 246.021 μs | 772.477 μs | 390.744 μs | 201.212 μs | 103.712 μs | — | — | 1.234 ms | 115.941 μs |
| maximum(norm) vec | Float32 256^3 | 15.152 ms | 8.494 ms | 5.995 ms | 5.604 ms | 7.503 ms | 3.522 ms | 2.099 ms | 2.089 ms | — | — | 2.782 ms | 365.655 μs |
| maximum(norm) vec | Float32 512^3 | — | — | — | — | 58.291 ms | 38.899 ms | 29.278 ms | 28.047 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 225.159 μs | 118.554 μs | 62.180 μs | 48.872 μs | 97.071 μs | 50.370 μs | 26.420 μs | 15.460 μs | — | — | 920.168 μs | 93.321 μs |
| maximum(norm) vec | Float64 128^3 | 5.345 ms | 2.715 ms | 1.393 ms | 846.954 μs | 1.580 ms | 795.558 μs | 400.774 μs | 204.562 μs | — | — | 1.571 ms | 216.182 μs |
| maximum(norm) vec | Float64 256^3 | 43.178 ms | 22.282 ms | 13.330 ms | 11.568 ms | 14.147 ms | 8.368 ms | 6.080 ms | 5.860 ms | — | — | 4.860 ms | 1.051 ms |
| maximum(norm) vec | Float64 512^3 | — | — | — | — | 126.692 ms | 73.096 ms | 57.719 ms | 56.885 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 651.615 μs | 337.108 μs | 170.646 μs | 90.136 μs | 196.732 μs | 101.611 μs | 52.360 μs | 28.390 μs | — | — | 979.833 μs | 100.421 μs |
| mean spectral vec | Float32 128^3 | 71.740 ns | 71.533 ns | 71.579 ns | 72.110 ns | 70.616 ns | 74.179 ns | 72.447 ns | 71.531 ns | — | — | 820.577 μs | 51.471 μs |
| mean spectral vec | Float32 256^3 | 72.239 ns | 72.320 ns | 72.756 ns | 72.872 ns | 71.119 ns | 75.293 ns | 73.717 ns | 71.900 ns | — | — | 812.941 μs | 49.990 μs |
| mean spectral vec | Float32 512^3 | — | — | — | — | 71.848 ns | 77.568 ns | 75.952 ns | 75.668 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 77.463 ns | 71.234 ns | 71.368 ns | 71.759 ns | 70.258 ns | 73.769 ns | 72.496 ns | 71.295 ns | — | — | 833.055 μs | 50.120 μs |
| mean spectral vec | Float64 128^3 | 77.758 ns | 73.848 ns | 74.286 ns | 74.398 ns | 76.210 ns | 79.104 ns | 78.333 ns | 80.456 ns | — | — | 814.812 μs | 58.231 μs |
| mean spectral vec | Float64 256^3 | 79.716 ns | 74.563 ns | 75.460 ns | 76.613 ns | 78.897 ns | 81.434 ns | 79.011 ns | 81.477 ns | — | — | 848.819 μs | 47.140 μs |
| mean spectral vec | Float64 512^3 | — | — | — | — | 80.031 ns | 83.966 ns | 83.134 ns | 86.210 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 73.504 ns | 73.021 ns | 72.737 ns | 73.951 ns | 80.508 ns | 80.745 ns | 77.880 ns | 81.841 ns | — | — | 830.467 μs | 47.770 μs |
| mean vector | Float32 128^3 | 521.620 μs | 319.670 μs | 194.991 μs | 114.663 μs | 194.042 μs | 107.401 μs | 63.710 μs | 44.761 μs | 633.756 μs | 4.808 ms | 1.887 ms | 172.472 μs |
| mean vector | Float32 256^3 | 7.827 ms | 6.072 ms | 5.559 ms | 5.436 ms | 3.465 ms | 2.670 ms | 2.396 ms | 2.415 ms | — | 16.657 ms | 5.531 ms | 637.218 μs |
| mean vector | Float32 512^3 | — | — | — | — | 31.587 ms | 27.203 ms | 26.862 ms | 27.171 ms | — | — | — | — |
| mean vector | Float32 64^3 | 49.165 μs | 34.264 μs | 25.674 μs | 31.341 μs | 24.960 μs | 17.480 μs | 12.950 μs | 15.591 μs | 162.362 μs | 1.846 ms | 1.302 ms | 163.812 μs |
| mean vector | Float64 128^3 | 1.648 ms | 1.053 ms | 849.643 μs | 793.726 μs | 400.084 μs | 206.192 μs | 121.701 μs | 82.151 μs | 657.486 μs | 5.195 ms | 1.836 ms | 200.792 μs |
| mean vector | Float64 256^3 | 14.983 ms | 12.972 ms | 11.806 ms | 11.316 ms | 8.677 ms | 6.527 ms | 6.571 ms | 6.650 ms | — | 17.799 ms | 6.369 ms | 677.607 μs |
| mean vector | Float64 512^3 | — | — | — | — | 59.314 ms | 56.142 ms | 54.490 ms | 54.876 ms | — | — | — | — |
| mean vector | Float64 64^3 | 92.415 μs | 63.766 μs | 41.668 μs | 40.850 μs | 45.720 μs | 31.090 μs | 20.011 μs | 18.930 μs | 156.311 μs | 1.913 ms | 1.281 ms | 143.312 μs |
| mean(det) tensor | Float32 128^3 | 2.495 ms | 1.968 ms | 1.694 ms | 1.532 ms | 773.138 μs | 381.133 μs | 196.882 μs | 120.681 μs | — | — | 1.280 ms | 226.472 μs |
| mean(det) tensor | Float32 256^3 | 24.807 ms | 21.499 ms | 19.098 ms | 17.978 ms | 15.340 ms | 11.632 ms | 10.382 ms | 10.387 ms | — | — | 3.413 ms | 835.851 μs |
| mean(det) tensor | Float32 512^3 | — | — | — | — | 107.381 ms | 89.687 ms | 84.190 ms | 85.147 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 103.122 μs | 61.466 μs | 29.994 μs | 21.224 μs | 67.100 μs | 36.870 μs | 23.440 μs | 14.580 μs | — | — | 937.045 μs | 99.801 μs |
| mean(det) tensor | Float64 128^3 | 5.384 ms | 4.754 ms | 4.222 ms | 3.863 ms | 2.576 ms | 1.547 ms | 1.200 ms | 1.211 ms | — | — | 1.491 ms | 293.243 μs |
| mean(det) tensor | Float64 256^3 | 46.354 ms | 44.532 ms | 38.506 ms | 37.166 ms | 30.727 ms | 23.328 ms | 21.606 ms | 21.519 ms | — | — | 4.560 ms | 1.535 ms |
| mean(det) tensor | Float64 512^3 | — | — | — | — | 197.593 ms | 180.352 ms | 168.578 ms | 169.265 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 233.464 μs | 129.918 μs | 74.662 μs | 41.508 μs | 134.761 μs | 67.741 μs | 44.781 μs | 28.990 μs | — | — | 972.637 μs | 97.821 μs |
| mean(norm) vec | Float32 128^3 | 1.589 ms | 806.356 μs | 407.919 μs | 212.917 μs | 607.256 μs | 302.083 μs | 159.612 μs | 82.771 μs | — | — | 538.869 μs | 108.001 μs |
| mean(norm) vec | Float32 256^3 | 13.152 ms | 7.866 ms | 5.982 ms | 5.545 ms | 6.276 ms | 3.626 ms | 2.072 ms | 2.088 ms | — | — | 2.833 ms | 360.335 μs |
| mean(norm) vec | Float32 512^3 | — | — | — | — | 51.540 ms | 37.026 ms | 29.491 ms | 28.177 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 193.009 μs | 99.359 μs | 53.467 μs | 31.969 μs | 76.500 μs | 39.891 μs | 21.240 μs | 15.961 μs | — | — | 921.051 μs | 97.771 μs |
| mean(norm) vec | Float64 128^3 | 5.283 ms | 2.668 ms | 1.367 ms | 852.780 μs | 1.429 ms | 723.817 μs | 364.374 μs | 190.242 μs | — | — | 1.332 ms | 229.192 μs |
| mean(norm) vec | Float64 256^3 | 42.797 ms | 21.618 ms | 13.196 ms | 11.503 ms | 13.150 ms | 8.153 ms | 6.190 ms | 5.822 ms | — | — | 4.325 ms | 947.129 μs |
| mean(norm) vec | Float64 512^3 | — | — | — | — | 116.479 ms | 71.465 ms | 57.533 ms | 56.762 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 644.557 μs | 332.750 μs | 168.447 μs | 89.317 μs | 180.422 μs | 92.741 μs | 47.760 μs | 26.530 μs | — | — | 957.695 μs | 95.531 μs |
| mean(tr) tensor | Float32 128^3 | 376.803 μs | 234.813 μs | 139.321 μs | 73.191 μs | 197.612 μs | 98.101 μs | 57.650 μs | 36.040 μs | — | — | 1.200 ms | 106.571 μs |
| mean(tr) tensor | Float32 256^3 | 6.684 ms | 6.358 ms | 5.667 ms | 5.460 ms | 3.098 ms | 2.414 ms | 2.137 ms | 2.248 ms | — | — | 2.699 ms | 358.075 μs |
| mean(tr) tensor | Float32 512^3 | — | — | — | — | 33.708 ms | 28.992 ms | 27.638 ms | 28.163 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 34.871 μs | 18.654 μs | 11.294 μs | 10.156 μs | 25.290 μs | 12.160 μs | 7.840 μs | 6.610 μs | — | — | 910.276 μs | 93.221 μs |
| mean(tr) tensor | Float64 128^3 | 1.325 ms | 985.412 μs | 838.504 μs | 748.239 μs | 407.964 μs | 181.662 μs | 100.601 μs | 72.231 μs | — | — | 1.170 ms | 147.592 μs |
| mean(tr) tensor | Float64 256^3 | 13.247 ms | 13.083 ms | 11.902 ms | 11.275 ms | 7.152 ms | 6.566 ms | 6.289 ms | 6.262 ms | — | — | 3.285 ms | 594.726 μs |
| mean(tr) tensor | Float64 512^3 | — | — | — | — | 65.938 ms | 60.227 ms | 55.773 ms | 56.596 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 67.856 μs | 37.556 μs | 20.285 μs | 15.147 μs | 43.300 μs | 24.240 μs | 14.460 μs | 10.011 μs | — | — | 921.594 μs | 90.111 μs |
| radial_correlation vec | Float32 128^3 | 37.712 ms | 33.033 ms | 35.793 ms | 36.040 ms | 30.705 ms | 22.879 ms | 21.468 ms | 20.363 ms | 5.783 ms | 42.875 ms | 2.515 ms | 665.806 μs |
| radial_correlation vec | Float32 256^3 | 447.565 ms | 308.865 ms | 277.883 ms | 264.189 ms | 385.168 ms | 264.612 ms | 195.467 ms | 171.916 ms | — | 185.439 ms | 10.286 ms | 5.622 ms |
| radial_correlation vec | Float32 512^3 | — | — | — | — | 2.757 s | 1.934 s | 1.351 s | 1.145 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.485 ms | 5.199 ms | 5.976 ms | 5.911 ms | 3.548 ms | 3.250 ms | 3.561 ms | 3.605 ms | 1.010 ms | 19.917 ms | 1.555 ms | 273.392 μs |
| radial_correlation vec | Float64 128^3 | 60.402 ms | 62.099 ms | 54.644 ms | 51.117 ms | 44.763 ms | 36.098 ms | 32.339 ms | 30.125 ms | 9.025 ms | 52.060 ms | 47.229 ms | 2.031 ms |
| radial_correlation vec | Float64 256^3 | 673.902 ms | 474.417 ms | 394.981 ms | 361.825 ms | 558.148 ms | 349.435 ms | 282.187 ms | 247.207 ms | — | 219.151 ms | 138.359 ms | 14.544 ms |
| radial_correlation vec | Float64 512^3 | — | — | — | — | 4.401 s | 2.851 s | 2.011 s | 1.735 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.555 ms | 5.140 ms | 5.663 ms | 5.733 ms | 3.810 ms | 3.281 ms | 3.342 ms | 3.208 ms | 1.413 ms | 21.203 ms | 23.553 ms | 311.313 μs |
| radial_spectrum vec | Float32 128^3 | 7.687 ms | 7.368 ms | 8.086 ms | 8.080 ms | 6.328 ms | 4.708 ms | 5.774 ms | 6.035 ms | 1.415 ms | 27.166 ms | 1.792 ms | 280.093 μs |
| radial_spectrum vec | Float32 256^3 | 61.536 ms | 48.600 ms | 45.891 ms | 43.702 ms | 50.100 ms | 32.849 ms | 31.389 ms | 30.048 ms | — | 96.772 ms | 3.246 ms | 940.122 μs |
| radial_spectrum vec | Float32 512^3 | — | — | — | — | 399.890 ms | 237.744 ms | 180.877 ms | 152.155 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 998.613 μs | 1.333 ms | 1.599 ms | 1.621 ms | 822.799 μs | 934.549 μs | 1.164 ms | 1.323 ms | 344.443 μs | 16.995 ms | 1.190 ms | 191.372 μs |
| radial_spectrum vec | Float64 128^3 | 7.731 ms | 6.612 ms | 5.934 ms | 5.548 ms | 6.548 ms | 4.606 ms | 4.452 ms | 4.572 ms | 1.515 ms | 29.791 ms | 28.854 ms | 421.274 μs |
| radial_spectrum vec | Float64 256^3 | 62.255 ms | 46.066 ms | 36.465 ms | 30.301 ms | 51.941 ms | 32.003 ms | 25.006 ms | 24.194 ms | — | 110.504 ms | 67.077 ms | 1.420 ms |
| radial_spectrum vec | Float64 512^3 | — | — | — | — | 414.296 ms | 251.291 ms | 163.540 ms | 126.319 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 1.008 ms | 774.067 μs | 1.104 ms | 1.102 ms | 848.879 μs | 683.176 μs | 836.318 μs | 939.811 μs | 380.613 μs | 16.740 ms | 15.470 ms | 192.401 μs |
| var scalar | Float32 128^3 | — | — | — | — | 132.961 μs | 78.660 μs | 42.360 μs | 28.331 μs | — | — | — | 138.472 μs |
| var scalar | Float32 256^3 | — | — | — | — | 1.274 ms | 647.997 μs | 336.603 μs | 198.012 μs | — | — | — | 435.685 μs |
| var scalar | Float32 512^3 | — | — | — | — | 29.830 ms | 19.872 ms | 17.961 ms | 18.160 ms | — | — | — | — |
| var scalar | Float32 64^3 | — | — | — | — | 14.620 μs | 8.940 μs | 7.561 μs | 8.970 μs | — | — | — | 123.921 μs |
| var scalar | Float64 128^3 | — | — | — | — | 253.612 μs | 127.801 μs | 73.641 μs | 50.001 μs | — | — | — | 155.162 μs |
| var scalar | Float64 256^3 | — | — | — | — | 4.187 ms | 2.206 ms | 1.771 ms | 1.833 ms | — | — | — | 492.935 μs |
| var scalar | Float64 512^3 | — | — | — | — | 42.689 ms | 39.502 ms | 36.150 ms | 36.107 ms | — | — | — | — |
| var scalar | Float64 64^3 | — | — | — | — | 32.290 μs | 17.540 μs | 11.161 μs | 11.540 μs | — | — | — | 122.062 μs |
| var spectral scalar | Float32 128^3 | — | — | — | — | 93.971 μs | 60.791 μs | 42.991 μs | 44.670 μs | — | — | — | 164.291 μs |
| var spectral scalar | Float32 256^3 | — | — | — | — | 776.578 μs | 464.185 μs | 298.323 μs | 242.862 μs | — | — | — | 285.604 μs |
| var spectral scalar | Float32 512^3 | — | — | — | — | 13.016 ms | 10.353 ms | 10.886 ms | 10.904 ms | — | — | — | — |
| var spectral scalar | Float32 64^3 | — | — | — | — | 11.390 μs | 8.260 μs | 7.280 μs | 9.510 μs | — | — | — | 174.452 μs |
| var spectral scalar | Float64 128^3 | — | — | — | — | 145.461 μs | 88.161 μs | 62.510 μs | 61.791 μs | — | — | — | 175.142 μs |
| var spectral scalar | Float64 256^3 | — | — | — | — | 1.920 ms | 1.407 ms | 1.062 ms | 1.064 ms | — | — | — | 344.444 μs |
| var spectral scalar | Float64 512^3 | — | — | — | — | 20.979 ms | 20.574 ms | 20.223 ms | 20.484 ms | — | — | — | — |
| var spectral scalar | Float64 64^3 | — | — | — | — | 20.050 μs | 12.771 μs | 9.590 μs | 9.820 μs | — | — | — | 166.312 μs |
| weighted_inner vec | Float32 128^3 | 12.776 ms | 12.629 ms | 12.608 ms | 12.786 ms | 10.331 ms | 10.361 ms | 10.329 ms | 10.399 ms | — | — | 1.428 ms | 139.152 μs |
| weighted_inner vec | Float32 256^3 | 100.807 ms | 100.234 ms | 99.130 ms | 100.881 ms | 81.280 ms | 81.461 ms | 81.071 ms | 81.487 ms | — | — | 4.280 ms | 638.068 μs |
| weighted_inner vec | Float32 512^3 | — | — | — | — | 644.959 ms | 646.977 ms | 646.111 ms | 646.434 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.629 ms | 1.624 ms | 1.626 ms | 1.629 ms | 1.338 ms | 1.284 ms | 1.282 ms | 1.342 ms | — | — | 1.020 ms | 99.181 μs |
| weighted_inner vec | Float64 128^3 | 13.991 ms | 13.956 ms | 13.886 ms | 13.759 ms | 10.903 ms | 10.889 ms | 10.885 ms | 10.936 ms | — | — | 1.679 ms | 170.192 μs |
| weighted_inner vec | Float64 256^3 | 110.973 ms | 111.552 ms | 111.245 ms | 108.115 ms | 85.750 ms | 85.740 ms | 85.753 ms | 85.955 ms | — | — | 5.232 ms | 1.075 ms |
| weighted_inner vec | Float64 512^3 | — | — | — | — | 680.557 ms | 681.377 ms | 681.191 ms | 681.869 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.725 ms | 1.725 ms | 1.722 ms | 1.715 ms | 1.352 ms | 1.353 ms | 1.415 ms | 1.415 ms | — | — | 1.040 ms | 99.561 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.869 ms | 12.646 ms | 12.697 ms | 12.786 ms | 10.368 ms | 10.364 ms | 10.358 ms | 10.386 ms | — | — | 1.362 ms | 156.992 μs |
| weighted_inner vec.vec | Float32 256^3 | 101.877 ms | 100.494 ms | 99.619 ms | 101.362 ms | 81.351 ms | 81.619 ms | 81.386 ms | 81.722 ms | — | — | 4.195 ms | 834.831 μs |
| weighted_inner vec.vec | Float32 512^3 | — | — | — | — | 646.322 ms | 647.232 ms | 647.402 ms | 647.589 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.632 ms | 1.626 ms | 1.628 ms | 1.599 ms | 1.338 ms | 1.283 ms | 1.289 ms | 1.353 ms | — | — | 1.001 ms | 93.401 μs |
| weighted_inner vec.vec | Float64 128^3 | 14.076 ms | 14.115 ms | 14.233 ms | 13.824 ms | 10.943 ms | 10.931 ms | 10.918 ms | 10.939 ms | — | — | 1.584 ms | 260.102 μs |
| weighted_inner vec.vec | Float64 256^3 | 112.210 ms | 112.428 ms | 114.038 ms | 110.747 ms | 86.026 ms | 86.096 ms | 85.923 ms | 86.087 ms | — | — | 5.332 ms | 1.545 ms |
| weighted_inner vec.vec | Float64 512^3 | — | — | — | — | 683.508 ms | 682.615 ms | 779.574 ms | 682.983 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.743 ms | 1.729 ms | 1.743 ms | 1.705 ms | 1.361 ms | 1.405 ms | 1.511 ms | 1.473 ms | — | — | 985.284 μs | 96.841 μs |

