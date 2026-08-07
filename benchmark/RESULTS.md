# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-08-07 at commit `bd1e4f30` on Julia 1.12.6, assembled on host `Aiporetne` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–**512³** both element types) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The pre-swap archive columns (GTX 1070, RX 6700 XT) keep their pre-rewrite measurements — retired hardware is not re-swept; every live column (both CPUs, RX 7900 XTX, RTX 5070 Ti) is measured at the decision-38/39 rewrite. **`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and the shift does not reproduce:** not one of that host's 48 `fft` rows per lane got slower, the ratios running 0.54–0.99 against its 2026-07-22 archive (median −6.5% at t1). `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. See PERFORMANCE.md §4(p). A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field. Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `264e9da8 @ 2026-08-05`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI; `bd1e4f30 @ 2026-08-07`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8, GPU 7900XTX; unstamped (vintage in the prose above): GPU 1070, GPU 6700XT. ~10% jitter.

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 3.940 ms | 2.704 ms | 2.251 ms | 2.117 ms | 2.785 ms | 1.468 ms | 825.039 μs | 526.065 μs | — | — | — | — |
| to_physical scalar measure | Float32 256^3 | 41.346 ms | 28.361 ms | 23.974 ms | 23.526 ms | 31.963 ms | 20.675 ms | 14.102 ms | 11.900 ms | — | — | — | — |
| to_physical scalar measure | Float32 512^3 | 520.095 ms | 274.759 ms | 231.175 ms | 274.469 ms | 359.936 ms | 196.036 ms | 145.811 ms | 131.356 ms | — | — | — | — |
| to_physical scalar measure | Float32 64^3 | 371.922 μs | 241.902 μs | 160.965 μs | 141.497 μs | 278.443 μs | 158.871 μs | 95.491 μs | 68.460 μs | — | — | — | — |
| to_physical scalar measure | Float64 128^3 | 6.068 ms | 5.522 ms | 5.182 ms | 4.508 ms | 3.966 ms | 2.459 ms | 1.450 ms | 1.164 ms | — | — | — | — |
| to_physical scalar measure | Float64 256^3 | 103.157 ms | 70.830 ms | 49.714 ms | 56.313 ms | 107.025 ms | 42.443 ms | 33.597 ms | 42.895 ms | — | — | — | — |
| to_physical scalar measure | Float64 512^3 | 1.102 s | 720.100 ms | 657.297 ms | 618.290 ms | 874.242 ms | 585.630 ms | 449.228 ms | 400.750 ms | — | — | — | — |
| to_physical scalar measure | Float64 64^3 | 545.365 μs | 351.124 μs | 260.592 μs | 226.641 μs | 373.384 μs | 207.822 μs | 133.082 μs | 101.711 μs | — | — | — | — |
| to_physical scalar | Float32 128^3 | 4.920 ms | 3.213 ms | 2.415 ms | 2.308 ms | 4.526 ms | 2.401 ms | 1.279 ms | 780.589 μs | 788.067 μs | 2.421 ms | 1.263 ms | 124.222 μs |
| to_physical scalar | Float32 256^3 | 88.021 ms | 49.841 ms | 33.533 ms | 26.385 ms | 167.481 ms | 89.002 ms | 48.071 ms | 28.070 ms | — | 7.945 ms | 2.203 ms | 1.092 ms |
| to_physical scalar | Float32 512^3 | 1.309 s | 667.091 ms | 506.857 ms | 390.054 ms | 2.032 s | 1.014 s | 557.968 ms | 323.605 ms | — | — | 13.435 ms | — |
| to_physical scalar | Float32 64^3 | 384.770 μs | 252.646 μs | 166.414 μs | 146.793 μs | 317.583 μs | 175.832 μs | 102.451 μs | 69.781 μs | 124.402 μs | 1.497 ms | 1.050 ms | 111.732 μs |
| to_physical scalar | Float64 128^3 | 7.749 ms | 5.805 ms | 4.775 ms | 4.337 ms | 10.016 ms | 5.395 ms | 3.045 ms | 1.833 ms | 1.905 ms | 3.750 ms | 1.770 ms | 518.486 μs |
| to_physical scalar | Float64 256^3 | 127.268 ms | 80.088 ms | 51.637 ms | 52.488 ms | 116.009 ms | 49.727 ms | 35.835 ms | 41.326 ms | — | 14.463 ms | 5.830 ms | 3.856 ms |
| to_physical scalar | Float64 512^3 | 1.450 s | 892.696 ms | 709.422 ms | 633.442 ms | 947.813 ms | 622.876 ms | 453.709 ms | 411.141 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 672.104 μs | 404.924 μs | 286.897 μs | 276.351 μs | 536.156 μs | 289.402 μs | 165.602 μs | 115.671 μs | 331.873 μs | 1.784 ms | 1.173 ms | 115.001 μs |
| to_physical vector measure | Float32 128^3 | 11.689 ms | 8.998 ms | 8.221 ms | 7.647 ms | 9.415 ms | 5.765 ms | 4.042 ms | 3.109 ms | — | — | — | — |
| to_physical vector measure | Float32 256^3 | 125.496 ms | 94.289 ms | 75.629 ms | 74.747 ms | 122.127 ms | 82.642 ms | 56.883 ms | 50.480 ms | — | — | — | — |
| to_physical vector measure | Float32 512^3 | 1.861 s | 1.311 s | 1.015 s | 912.763 ms | 1.414 s | 991.823 ms | 726.002 ms | 636.295 ms | — | — | — | — |
| to_physical vector measure | Float32 64^3 | 1.231 ms | 809.758 μs | 564.304 μs | 498.312 μs | 876.529 μs | 496.044 μs | 299.443 μs | 223.762 μs | — | — | — | — |
| to_physical vector measure | Float64 128^3 | 30.774 ms | 18.363 ms | 21.288 ms | 27.609 ms | 22.716 ms | 17.022 ms | 13.803 ms | 13.878 ms | — | — | — | — |
| to_physical vector measure | Float64 256^3 | 361.550 ms | 268.443 ms | 234.660 ms | 227.607 ms | 333.875 ms | 223.494 ms | 171.643 ms | 152.791 ms | — | — | — | — |
| to_physical vector measure | Float64 512^3 | 3.338 s | 2.365 s | 2.031 s | 1.797 s | 2.593 s | 1.791 s | 1.364 s | 1.214 s | — | — | — | — |
| to_physical vector measure | Float64 64^3 | 1.988 ms | 1.748 ms | 1.271 ms | 1.358 ms | 1.119 ms | 682.937 μs | 417.264 μs | 346.084 μs | — | — | — | — |
| to_physical vector | Float32 128^3 | 14.719 ms | 11.254 ms | 7.979 ms | 7.291 ms | 14.547 ms | 10.047 ms | 5.498 ms | 3.994 ms | 2.507 ms | 4.595 ms | 1.614 ms | 303.383 μs |
| to_physical vector | Float32 256^3 | 263.761 ms | 187.728 ms | 116.684 ms | 97.607 ms | 530.370 ms | 362.577 ms | 189.015 ms | 135.163 ms | — | 14.844 ms | 5.541 ms | 3.483 ms |
| to_physical vector | Float32 512^3 | 4.218 s | 2.962 s | 1.764 s | 1.387 s | 6.317 s | 4.303 s | 2.323 s | 1.656 s | — | — | 51.822 ms | — |
| to_physical vector | Float32 64^3 | 1.273 ms | 984.725 μs | 561.725 μs | 481.941 μs | 1.011 ms | 679.717 μs | 319.633 μs | 221.832 μs | 380.054 μs | 1.776 ms | 1.187 ms | 129.711 μs |
| to_physical vector | Float64 128^3 | 35.147 ms | 19.672 ms | 25.810 ms | 25.688 ms | 40.341 ms | 28.484 ms | 19.360 ms | 16.772 ms | 5.630 ms | 8.090 ms | 2.747 ms | 1.490 ms |
| to_physical vector | Float64 256^3 | 435.564 ms | 343.093 ms | 242.970 ms | 228.550 ms | 357.403 ms | 272.826 ms | 176.757 ms | 156.240 ms | — | 22.812 ms | 13.485 ms | 11.385 ms |
| to_physical vector | Float64 512^3 | 4.538 s | 3.422 s | 2.259 s | 2.009 s | 2.810 s | 2.143 s | 1.423 s | 1.275 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.542 ms | 2.131 ms | 1.398 ms | 1.193 ms | 1.668 ms | 1.146 ms | 578.566 μs | 423.715 μs | 811.437 μs | 2.301 ms | 1.295 ms | 203.792 μs |
| to_spectral scalar measure | Float32 128^3 | 3.332 ms | 2.325 ms | 1.567 ms | 1.196 ms | 2.798 ms | 1.424 ms | 787.478 μs | 478.735 μs | — | — | — | — |
| to_spectral scalar measure | Float32 256^3 | 35.032 ms | 22.432 ms | 19.125 ms | 18.101 ms | 36.744 ms | 21.261 ms | 13.615 ms | 10.554 ms | — | — | — | — |
| to_spectral scalar measure | Float32 512^3 | 488.544 ms | 224.043 ms | 271.721 ms | 267.653 ms | 369.629 ms | 171.988 ms | 113.206 ms | 98.470 ms | — | — | — | — |
| to_spectral scalar measure | Float32 64^3 | 362.043 μs | 202.388 μs | 136.870 μs | 98.325 μs | 279.603 μs | 146.462 μs | 85.271 μs | 57.180 μs | — | — | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.352 ms | 4.279 ms | 3.655 ms | 3.403 ms | 3.870 ms | 2.396 ms | 1.511 ms | 894.330 μs | — | — | — | — |
| to_spectral scalar measure | Float64 256^3 | 96.587 ms | 68.564 ms | 38.813 ms | 62.826 ms | 93.751 ms | 40.189 ms | 26.642 ms | 31.053 ms | — | — | — | — |
| to_spectral scalar measure | Float64 512^3 | 1.088 s | 631.184 ms | 567.274 ms | 527.390 ms | 772.885 ms | 509.036 ms | 383.774 ms | 332.050 ms | — | — | — | — |
| to_spectral scalar measure | Float64 64^3 | 498.914 μs | 294.077 μs | 194.581 μs | 228.182 μs | 347.094 μs | 190.351 μs | 114.911 μs | 74.781 μs | — | — | — | — |
| to_spectral scalar | Float32 128^3 | 4.355 ms | 2.699 ms | 1.747 ms | 1.679 ms | 4.489 ms | 2.309 ms | 1.252 ms | 739.548 μs | 488.254 μs | 2.072 ms | 1.105 ms | 99.241 μs |
| to_spectral scalar | Float32 256^3 | 84.124 ms | 45.903 ms | 29.063 ms | 21.624 ms | 167.145 ms | 87.126 ms | 46.049 ms | 26.208 ms | — | 5.009 ms | 1.577 ms | 748.598 μs |
| to_spectral scalar | Float32 512^3 | 1.289 s | 647.466 ms | 480.683 ms | 353.029 ms | 1.959 s | 982.890 ms | 515.588 ms | 290.158 ms | — | — | 9.487 ms | — |
| to_spectral scalar | Float32 64^3 | 363.076 μs | 209.386 μs | 130.953 μs | 105.406 μs | 306.333 μs | 164.582 μs | 90.661 μs | 59.350 μs | 89.181 μs | 1.538 ms | 943.395 μs | 79.591 μs |
| to_spectral scalar | Float64 128^3 | 6.933 ms | 5.128 ms | 3.945 ms | 3.368 ms | 9.960 ms | 5.640 ms | 2.995 ms | 1.677 ms | 1.501 ms | 3.125 ms | 1.410 ms | 452.815 μs |
| to_spectral scalar | Float64 256^3 | 140.834 ms | 87.104 ms | 46.038 ms | 64.462 ms | 207.406 ms | 91.751 ms | 53.049 ms | 46.783 ms | — | 12.871 ms | 5.272 ms | 3.135 ms |
| to_spectral scalar | Float64 512^3 | 1.577 s | 880.360 ms | 659.997 ms | 549.715 ms | 1.712 s | 974.684 ms | 601.319 ms | 434.228 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 631.171 μs | 355.908 μs | 222.473 μs | 195.482 μs | 516.766 μs | 274.303 μs | 153.801 μs | 96.421 μs | 265.683 μs | 1.745 ms | 925.610 μs | 103.951 μs |
| to_spectral vector measure | Float32 128^3 | 10.269 ms | 7.369 ms | 5.918 ms | 5.451 ms | 9.863 ms | 5.945 ms | 3.568 ms | 2.711 ms | — | — | — | — |
| to_spectral vector measure | Float32 256^3 | 106.816 ms | 72.627 ms | 59.081 ms | 58.272 ms | 130.782 ms | 77.203 ms | 47.618 ms | 41.221 ms | — | — | — | — |
| to_spectral vector measure | Float32 512^3 | 1.730 s | 1.170 s | 869.340 ms | 751.569 ms | 1.401 s | 904.170 ms | 636.487 ms | 530.718 ms | — | — | — | — |
| to_spectral vector measure | Float32 64^3 | 1.124 ms | 689.278 μs | 468.611 μs | 381.687 μs | 883.499 μs | 480.625 μs | 264.803 μs | 199.102 μs | — | — | — | — |
| to_spectral vector measure | Float64 128^3 | 27.195 ms | 15.470 ms | 22.360 ms | 12.680 ms | 23.967 ms | 17.468 ms | 13.240 ms | 13.115 ms | — | — | — | — |
| to_spectral vector measure | Float64 256^3 | 342.075 ms | 244.051 ms | 198.161 ms | 185.245 ms | 289.988 ms | 198.167 ms | 138.329 ms | 125.640 ms | — | — | — | — |
| to_spectral vector measure | Float64 512^3 | 3.271 s | 2.198 s | 1.720 s | 1.513 s | 2.247 s | 1.534 s | 1.163 s | 984.517 ms | — | — | — | — |
| to_spectral vector measure | Float64 64^3 | 1.791 ms | 1.443 ms | 985.889 μs | 718.537 μs | 1.061 ms | 649.717 μs | 374.813 μs | 275.723 μs | — | — | — | — |
| to_spectral vector | Float32 128^3 | 13.253 ms | 9.696 ms | 6.487 ms | 5.719 ms | 14.586 ms | 10.454 ms | 5.014 ms | 3.559 ms | 1.355 ms | 3.183 ms | 1.287 ms | 198.662 μs |
| to_spectral vector | Float32 256^3 | 257.120 ms | 178.171 ms | 99.371 ms | 80.132 ms | 522.037 ms | 352.782 ms | 177.434 ms | 123.615 ms | — | 11.819 ms | 3.387 ms | 2.215 ms |
| to_spectral vector | Float32 512^3 | 4.109 s | 2.923 s | 1.634 s | 1.256 s | 6.251 s | 4.283 s | 2.239 s | 1.570 s | — | — | 20.298 ms | — |
| to_spectral vector | Float32 64^3 | 1.205 ms | 875.734 μs | 475.570 μs | 395.918 μs | 971.561 μs | 652.406 μs | 285.753 μs | 181.042 μs | 230.522 μs | 1.566 ms | 962.362 μs | 94.591 μs |
| to_spectral vector | Float64 128^3 | 32.548 ms | 18.443 ms | 22.319 ms | 12.273 ms | 41.049 ms | 30.695 ms | 19.224 ms | 16.661 ms | 4.144 ms | 6.538 ms | 2.247 ms | 1.180 ms |
| to_spectral vector | Float64 256^3 | 488.801 ms | 367.693 ms | 232.568 ms | 204.396 ms | 634.829 ms | 450.086 ms | 252.364 ms | 197.484 ms | — | 20.041 ms | 11.724 ms | 9.226 ms |
| to_spectral vector | Float64 512^3 | 4.975 s | 3.661 s | 2.193 s | 1.837 s | 5.124 s | 3.636 s | 2.044 s | 1.600 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.079 ms | 1.860 ms | 1.176 ms | 806.065 μs | 1.564 ms | 1.086 ms | 532.105 μs | 347.664 μs | 596.836 μs | 2.151 ms | 1.108 ms | 208.532 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 388.209 μs | 236.369 μs | 170.421 μs | 74.913 μs | 161.342 μs | 83.991 μs | 43.720 μs | 36.420 μs | 351.303 μs | 1.943 ms | 969.961 μs | 81.390 μs |
| add! scalar | Float32 256^3 | 8.073 ms | 7.299 ms | 5.615 ms | 5.178 ms | 3.479 ms | 2.948 ms | 2.727 ms | 2.807 ms | — | 6.480 ms | 1.864 ms | 329.123 μs |
| add! scalar | Float32 512^3 | 68.673 ms | 62.603 ms | 48.877 ms | 45.609 ms | 40.681 ms | 36.541 ms | 36.661 ms | 37.270 ms | — | — | 7.606 ms | — |
| add! scalar | Float32 64^3 | 42.178 μs | 22.703 μs | 10.208 μs | 9.854 μs | 22.621 μs | 12.771 μs | 7.010 μs | 6.350 μs | 85.391 μs | 1.599 ms | 1.079 ms | 70.130 μs |
| add! scalar | Float64 128^3 | 1.461 ms | 1.286 ms | 958.019 μs | 807.698 μs | 320.173 μs | 163.672 μs | 87.861 μs | 72.281 μs | 354.693 μs | 2.024 ms | 1.155 ms | 100.541 μs |
| add! scalar | Float64 256^3 | 15.938 ms | 15.300 ms | 11.800 ms | 10.935 ms | 10.097 ms | 8.732 ms | 8.338 ms | 8.529 ms | — | 5.550 ms | 1.973 ms | 562.466 μs |
| add! scalar | Float64 512^3 | 136.659 ms | 126.580 ms | 97.743 ms | 91.293 ms | 84.255 ms | 73.021 ms | 73.450 ms | 74.194 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 83.825 μs | 51.628 μs | 21.309 μs | 18.978 μs | 39.791 μs | 22.740 μs | 12.030 μs | 9.820 μs | 83.741 μs | 1.494 ms | 844.033 μs | 58.210 μs |
| combine! vec | Float32 128^3 | 2.597 ms | 2.332 ms | 1.819 ms | 1.600 ms | 632.417 μs | 324.984 μs | 162.262 μs | 112.461 μs | — | — | 1.473 ms | 186.562 μs |
| combine! vec | Float32 256^3 | 25.251 ms | 23.119 ms | 18.200 ms | 16.717 ms | 13.778 ms | 13.637 ms | 13.738 ms | 13.953 ms | — | — | 4.171 ms | 1.017 ms |
| combine! vec | Float32 512^3 | 207.335 ms | 185.538 ms | 148.923 ms | 138.000 ms | 116.665 ms | 106.896 ms | 110.713 ms | 111.740 ms | — | — | 19.321 ms | — |
| combine! vec | Float32 64^3 | 126.992 μs | 69.138 μs | 39.003 μs | 20.367 μs | 66.031 μs | 34.531 μs | 20.580 μs | 14.371 μs | — | — | 1.135 ms | 74.231 μs |
| combine! vec | Float64 128^3 | 5.894 ms | 5.405 ms | 4.131 ms | 3.742 ms | 2.241 ms | 1.868 ms | 1.547 ms | 1.517 ms | — | — | 1.626 ms | 258.423 μs |
| combine! vec | Float64 256^3 | 49.976 ms | 46.284 ms | 36.866 ms | 34.033 ms | 28.298 ms | 26.631 ms | 27.010 ms | 27.738 ms | — | — | 4.954 ms | 1.593 ms |
| combine! vec | Float64 512^3 | 407.338 ms | 375.527 ms | 293.122 ms | 275.044 ms | 226.533 ms | 219.380 ms | 218.729 ms | 221.268 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 260.077 μs | 140.990 μs | 81.376 μs | 46.383 μs | 122.971 μs | 64.360 μs | 34.381 μs | 28.571 μs | — | — | 1.007 ms | 65.860 μs |
| cross! | Float32 128^3 | 2.931 ms | 2.398 ms | 2.118 ms | 1.967 ms | 1.986 ms | 970.939 μs | 479.095 μs | 250.383 μs | 1.223 ms | 3.445 ms | 957.861 μs | 127.131 μs |
| cross! | Float32 256^3 | 27.269 ms | 24.773 ms | 23.393 ms | 22.109 ms | 24.035 ms | 14.378 ms | 12.381 ms | 12.442 ms | — | 14.690 ms | 1.648 ms | 830.189 μs |
| cross! | Float32 512^3 | 227.705 ms | 202.770 ms | 192.348 ms | 183.951 ms | 190.976 ms | 116.522 ms | 111.647 ms | 111.178 ms | — | — | 7.536 ms | — |
| cross! | Float32 64^3 | 256.097 μs | 132.155 μs | 68.616 μs | 38.814 μs | 235.972 μs | 115.681 μs | 59.851 μs | 32.890 μs | 219.582 μs | 1.665 ms | 1.061 ms | 59.271 μs |
| cross! | Float64 128^3 | 6.250 ms | 5.759 ms | 5.075 ms | 4.877 ms | 3.792 ms | 2.317 ms | 1.580 ms | 1.492 ms | 1.263 ms | 2.603 ms | 1.541 ms | 278.063 μs |
| cross! | Float64 256^3 | 52.123 ms | 50.663 ms | 47.305 ms | 45.604 ms | 42.542 ms | 29.897 ms | 27.020 ms | 27.256 ms | — | 15.625 ms | 2.608 ms | 1.595 ms |
| cross! | Float64 512^3 | 412.992 ms | 409.844 ms | 382.736 ms | 369.731 ms | 316.778 ms | 232.816 ms | 220.539 ms | 220.836 ms | — | — | — | — |
| cross! | Float64 64^3 | 358.517 μs | 184.977 μs | 96.655 μs | 54.729 μs | 225.132 μs | 115.861 μs | 59.500 μs | 36.241 μs | 216.592 μs | 1.846 ms | 971.775 μs | 65.651 μs |
| det! tensor | Float32 128^3 | 3.328 ms | 2.464 ms | 2.006 ms | 1.795 ms | 2.166 ms | 1.081 ms | 547.135 μs | 290.473 μs | — | — | 1.044 ms | 184.282 μs |
| det! tensor | Float32 256^3 | 33.753 ms | 25.624 ms | 22.255 ms | 19.874 ms | 30.909 ms | 18.014 ms | 12.000 ms | 11.942 ms | — | — | 2.242 ms | 912.229 μs |
| det! tensor | Float32 512^3 | 246.816 ms | 196.652 ms | 180.822 ms | 165.881 ms | 211.147 ms | 124.395 ms | 104.433 ms | 104.939 ms | — | — | 9.284 ms | — |
| det! tensor | Float32 64^3 | 306.996 μs | 162.094 μs | 81.729 μs | 46.453 μs | 255.553 μs | 128.791 μs | 65.551 μs | 36.401 μs | — | — | 1.037 ms | 78.881 μs |
| det! tensor | Float64 128^3 | 6.405 ms | 5.546 ms | 4.775 ms | 4.289 ms | 4.005 ms | 2.560 ms | 1.685 ms | 1.609 ms | — | — | 1.362 ms | 260.493 μs |
| det! tensor | Float64 256^3 | 48.213 ms | 48.572 ms | 43.502 ms | 39.145 ms | 41.957 ms | 29.101 ms | 25.715 ms | 25.576 ms | — | — | 3.103 ms | 1.816 ms |
| det! tensor | Float64 512^3 | 374.082 ms | 400.702 ms | 340.725 ms | 309.426 ms | 409.421 ms | 246.752 ms | 206.794 ms | 209.257 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 353.499 μs | 191.768 μs | 105.859 μs | 62.011 μs | 253.163 μs | 152.552 μs | 75.091 μs | 42.051 μs | — | — | 925.912 μs | 67.921 μs |
| dot! vec.vec | Float32 128^3 | 2.801 ms | 1.659 ms | 1.250 ms | 1.094 ms | 2.453 ms | 1.246 ms | 626.926 μs | 322.663 μs | 538.855 μs | 2.430 ms | 1.154 ms | 112.321 μs |
| dot! vec.vec | Float32 256^3 | 23.089 ms | 16.664 ms | 15.307 ms | 13.902 ms | 22.526 ms | 11.397 ms | 8.105 ms | 8.032 ms | — | 9.651 ms | 2.356 ms | 667.826 μs |
| dot! vec.vec | Float32 512^3 | 197.477 ms | 138.245 ms | 125.530 ms | 114.873 ms | 170.914 ms | 92.426 ms | 76.011 ms | 76.057 ms | — | — | 10.182 ms | — |
| dot! vec.vec | Float32 64^3 | 329.279 μs | 201.884 μs | 104.408 μs | 59.006 μs | 308.574 μs | 159.962 μs | 81.741 μs | 44.040 μs | 112.901 μs | 1.663 ms | 1.092 ms | 68.330 μs |
| dot! vec.vec | Float64 128^3 | 4.241 ms | 3.743 ms | 3.108 ms | 2.856 ms | 3.493 ms | 1.737 ms | 887.879 μs | 639.157 μs | 618.906 μs | 2.505 ms | 1.152 ms | 193.872 μs |
| dot! vec.vec | Float64 256^3 | 39.060 ms | 35.067 ms | 29.190 ms | 26.830 ms | 36.896 ms | 19.597 ms | 17.904 ms | 17.997 ms | — | 9.784 ms | 3.014 ms | 1.218 ms |
| dot! vec.vec | Float64 512^3 | 297.167 ms | 278.968 ms | 232.243 ms | 216.914 ms | 228.498 ms | 158.762 ms | 148.040 ms | 151.292 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 337.330 μs | 213.313 μs | 106.683 μs | 63.337 μs | 317.754 μs | 159.121 μs | 81.631 μs | 44.221 μs | 127.611 μs | 1.656 ms | 964.066 μs | 62.510 μs |
| map!(+) vec | Float32 128^3 | 2.918 ms | 2.404 ms | 2.077 ms | 1.970 ms | 1.611 ms | 807.878 μs | 400.584 μs | 208.092 μs | — | — | 983.684 μs | 120.721 μs |
| map!(+) vec | Float32 256^3 | 27.153 ms | 24.773 ms | 23.295 ms | 22.193 ms | 21.415 ms | 14.028 ms | 12.396 ms | 12.455 ms | — | — | 1.752 ms | 829.909 μs |
| map!(+) vec | Float32 512^3 | 224.921 ms | 202.036 ms | 192.171 ms | 183.733 ms | 179.107 ms | 115.435 ms | 111.688 ms | 111.266 ms | — | — | 8.206 ms | — |
| map!(+) vec | Float32 64^3 | 246.068 μs | 129.376 μs | 69.145 μs | 37.851 μs | 175.802 μs | 95.001 μs | 48.590 μs | 27.490 μs | — | — | 1.088 ms | 55.801 μs |
| map!(+) vec | Float64 128^3 | 6.207 ms | 5.662 ms | 5.053 ms | 4.902 ms | 3.717 ms | 2.254 ms | 1.564 ms | 1.506 ms | — | — | 1.189 ms | 279.963 μs |
| map!(+) vec | Float64 256^3 | 51.690 ms | 50.585 ms | 47.081 ms | 45.616 ms | 39.252 ms | 29.601 ms | 27.023 ms | 27.288 ms | — | — | 2.588 ms | 1.600 ms |
| map!(+) vec | Float64 512^3 | 408.672 ms | 409.233 ms | 381.435 ms | 368.940 ms | 309.853 ms | 226.512 ms | 221.559 ms | 219.295 ms | — | — | — | — |
| map!(+) vec | Float64 64^3 | 347.120 μs | 185.466 μs | 99.091 μs | 55.074 μs | 199.612 μs | 94.581 μs | 48.501 μs | 31.940 μs | — | — | 880.771 μs | 63.831 μs |
| map!(det) tensor | Float32 128^3 | 3.299 ms | 2.463 ms | 1.944 ms | 1.780 ms | 2.151 ms | 1.081 ms | 547.785 μs | 286.693 μs | — | — | 440.955 μs | 181.881 μs |
| map!(det) tensor | Float32 256^3 | 33.741 ms | 25.569 ms | 21.965 ms | 19.736 ms | 30.749 ms | 18.289 ms | 12.020 ms | 11.953 ms | — | — | 1.973 ms | 884.889 μs |
| map!(det) tensor | Float32 512^3 | 245.565 ms | 196.788 ms | 179.313 ms | 164.276 ms | 215.387 ms | 124.185 ms | 104.338 ms | 105.084 ms | — | — | 8.624 ms | — |
| map!(det) tensor | Float32 64^3 | 302.407 μs | 157.977 μs | 79.788 μs | 48.134 μs | 251.253 μs | 127.811 μs | 65.521 μs | 36.231 μs | — | — | 968.191 μs | 71.431 μs |
| map!(det) tensor | Float64 128^3 | 6.411 ms | 5.559 ms | 4.790 ms | 4.298 ms | 3.999 ms | 2.486 ms | 1.679 ms | 1.607 ms | — | — | 1.235 ms | 266.122 μs |
| map!(det) tensor | Float64 256^3 | 48.213 ms | 48.708 ms | 43.442 ms | 39.103 ms | 41.941 ms | 28.988 ms | 25.660 ms | 26.193 ms | — | — | 2.898 ms | 1.830 ms |
| map!(det) tensor | Float64 512^3 | 373.637 ms | 400.176 ms | 342.339 ms | 309.659 ms | 398.621 ms | 237.563 ms | 206.237 ms | 208.857 ms | — | — | — | — |
| map!(det) tensor | Float64 64^3 | 351.321 μs | 184.872 μs | 107.432 μs | 62.416 μs | 251.632 μs | 129.851 μs | 66.161 μs | 42.151 μs | — | — | 841.800 μs | 75.380 μs |
| mul! tensor.vec | Float32 128^3 | 5.085 ms | 4.259 ms | 3.736 ms | 3.545 ms | 3.368 ms | 1.971 ms | 1.060 ms | 766.088 μs | 1.525 ms | 4.295 ms | 1.231 ms | 208.463 μs |
| mul! tensor.vec | Float32 256^3 | 48.770 ms | 40.311 ms | 37.044 ms | 34.905 ms | 32.923 ms | 28.940 ms | 20.935 ms | 20.943 ms | — | 16.892 ms | 2.472 ms | 1.315 ms |
| mul! tensor.vec | Float32 512^3 | 403.678 ms | 313.946 ms | 302.395 ms | 285.772 ms | 347.679 ms | 215.344 ms | 178.840 ms | 175.320 ms | — | — | 12.172 ms | — |
| mul! tensor.vec | Float32 64^3 | 434.693 μs | 234.878 μs | 121.989 μs | 67.468 μs | 372.604 μs | 212.232 μs | 107.341 μs | 58.021 μs | 255.702 μs | 1.882 ms | 1.049 ms | 74.300 μs |
| mul! tensor.vec | Float64 128^3 | 10.698 ms | 9.242 ms | 9.156 ms | 8.672 ms | 7.015 ms | 5.490 ms | 4.516 ms | 4.313 ms | 1.748 ms | 4.757 ms | 1.346 ms | 394.614 μs |
| mul! tensor.vec | Float64 256^3 | 80.789 ms | 78.511 ms | 74.473 ms | 71.012 ms | 57.331 ms | 50.796 ms | 43.292 ms | 43.693 ms | — | 17.818 ms | 3.936 ms | 2.568 ms |
| mul! tensor.vec | Float64 512^3 | 606.952 ms | 632.000 ms | 592.094 ms | 565.883 ms | 574.679 ms | 384.477 ms | 346.964 ms | 346.037 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 704.424 μs | 457.010 μs | 344.518 μs | 204.337 μs | 377.394 μs | 214.922 μs | 109.261 μs | 60.791 μs | 280.183 μs | 1.951 ms | 949.175 μs | 79.781 μs |
| norm! vec | Float32 128^3 | 805.111 μs | 580.083 μs | 465.693 μs | 339.052 μs | 215.802 μs | 116.272 μs | 62.621 μs | 54.290 μs | 411.304 μs | 2.110 ms | 950.681 μs | 87.961 μs |
| norm! vec | Float32 256^3 | 10.068 ms | 9.420 ms | 7.829 ms | 7.169 ms | 5.312 ms | 4.313 ms | 4.113 ms | 4.239 ms | — | 7.304 ms | 2.021 ms | 392.964 μs |
| norm! vec | Float32 512^3 | 82.552 ms | 80.164 ms | 66.460 ms | 62.401 ms | 53.474 ms | 46.026 ms | 46.323 ms | 46.766 ms | — | — | 7.833 ms | — |
| norm! vec | Float32 64^3 | 53.448 μs | 38.390 μs | 19.352 μs | 16.953 μs | 32.151 μs | 20.990 μs | 12.990 μs | 11.351 μs | 100.251 μs | 1.526 ms | 1.064 ms | 53.610 μs |
| norm! vec | Float64 128^3 | 2.096 ms | 1.912 ms | 1.478 ms | 1.341 ms | 475.805 μs | 247.272 μs | 130.861 μs | 103.532 μs | 463.344 μs | 1.434 ms | 1.402 ms | 177.462 μs |
| norm! vec | Float64 256^3 | 21.357 ms | 19.485 ms | 16.164 ms | 15.044 ms | 11.860 ms | 10.276 ms | 10.240 ms | 10.511 ms | — | 9.850 ms | 3.290 ms | 718.727 μs |
| norm! vec | Float64 512^3 | 165.424 ms | 159.487 ms | 133.072 ms | 124.108 ms | 98.096 ms | 91.879 ms | 91.944 ms | 93.394 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 157.715 μs | 89.236 μs | 50.120 μs | 32.556 μs | 56.541 μs | 34.910 μs | 20.910 μs | 16.131 μs | 101.231 μs | 1.681 ms | 1.077 ms | 66.380 μs |
| tr! tensor | Float32 128^3 | 691.097 μs | 523.363 μs | 440.842 μs | 322.273 μs | 213.522 μs | 113.371 μs | 59.850 μs | 50.970 μs | — | — | 960.719 μs | 85.880 μs |
| tr! tensor | Float32 256^3 | 10.241 ms | 9.433 ms | 7.656 ms | 7.048 ms | 5.143 ms | 4.389 ms | 4.285 ms | 4.395 ms | — | — | 2.017 ms | 390.684 μs |
| tr! tensor | Float32 512^3 | 84.908 ms | 77.523 ms | 64.685 ms | 61.041 ms | 48.439 ms | 45.246 ms | 46.314 ms | 46.857 ms | — | — | 8.455 ms | — |
| tr! tensor | Float32 64^3 | 52.733 μs | 32.379 μs | 15.337 μs | 13.594 μs | 27.520 μs | 18.070 μs | 11.310 μs | 9.240 μs | — | — | 1.065 ms | 70.371 μs |
| tr! tensor | Float64 128^3 | 2.087 ms | 1.877 ms | 1.437 ms | 1.305 ms | 459.104 μs | 237.062 μs | 123.722 μs | 99.031 μs | — | — | 1.238 ms | 118.612 μs |
| tr! tensor | Float64 256^3 | 20.335 ms | 19.187 ms | 15.923 ms | 14.596 ms | 11.679 ms | 10.572 ms | 10.558 ms | 10.700 ms | — | — | 2.279 ms | 725.297 μs |
| tr! tensor | Float64 512^3 | 153.574 ms | 155.349 ms | 130.436 ms | 121.342 ms | 105.082 ms | 91.770 ms | 92.929 ms | 94.273 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 104.769 μs | 60.834 μs | 34.275 μs | 19.486 μs | 53.781 μs | 31.390 μs | 18.790 μs | 13.990 μs | — | — | 839.270 μs | 57.131 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.570 ms | 2.817 ms | 1.534 ms | 1.201 ms | 3.206 ms | 1.657 ms | 835.459 μs | 427.495 μs | 697.807 μs | 2.544 ms | 1.200 ms | 96.391 μs |
| curl! vec->vec | Float32 256^3 | 44.143 ms | 22.594 ms | 17.329 ms | 16.603 ms | 25.705 ms | 13.142 ms | 8.876 ms | 8.782 ms | — | 10.865 ms | 1.570 ms | 603.926 μs |
| curl! vec->vec | Float32 512^3 | 352.634 ms | 178.081 ms | 143.986 ms | 137.109 ms | 206.734 ms | 108.282 ms | 84.698 ms | 83.799 ms | — | — | 6.308 ms | — |
| curl! vec->vec | Float32 64^3 | 701.076 μs | 360.763 μs | 183.790 μs | 97.418 μs | 417.165 μs | 216.872 μs | 109.911 μs | 58.010 μs | 182.902 μs | 1.646 ms | 976.669 μs | 67.821 μs |
| curl! vec->vec | Float64 128^3 | 5.472 ms | 3.970 ms | 3.543 ms | 3.407 ms | 3.699 ms | 1.861 ms | 951.380 μs | 538.286 μs | 824.588 μs | 3.153 ms | 1.394 ms | 209.672 μs |
| curl! vec->vec | Float64 256^3 | 48.491 ms | 38.152 ms | 35.526 ms | 34.402 ms | 32.969 ms | 20.119 ms | 19.345 ms | 20.601 ms | — | 13.647 ms | 3.071 ms | 1.123 ms |
| curl! vec->vec | Float64 512^3 | 357.994 ms | 295.934 ms | 285.142 ms | 276.230 ms | 238.336 ms | 165.155 ms | 164.326 ms | 165.950 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 669.677 μs | 353.934 μs | 178.966 μs | 98.998 μs | 469.475 μs | 237.312 μs | 115.842 μs | 64.781 μs | 186.242 μs | 1.786 ms | 959.981 μs | 78.651 μs |
| divergence! vec->scalar | Float32 128^3 | 3.488 ms | 1.379 ms | 714.512 μs | 410.273 μs | 3.349 ms | 1.120 ms | 557.196 μs | 291.933 μs | 326.353 μs | 1.957 ms | 1.082 ms | 90.970 μs |
| divergence! vec->scalar | Float32 256^3 | 28.222 ms | 11.020 ms | 9.254 ms | 8.271 ms | 26.643 ms | 8.971 ms | 4.540 ms | 4.136 ms | — | 5.523 ms | 1.513 ms | 407.894 μs |
| divergence! vec->scalar | Float32 512^3 | 225.599 ms | 89.683 ms | 78.305 ms | 70.431 ms | 211.213 ms | 70.610 ms | 46.833 ms | 46.802 ms | — | — | 7.241 ms | — |
| divergence! vec->scalar | Float32 64^3 | 427.450 μs | 176.172 μs | 92.150 μs | 51.564 μs | 434.305 μs | 151.492 μs | 78.480 μs | 42.921 μs | 93.900 μs | 1.537 ms | 1.038 ms | 64.510 μs |
| divergence! vec->scalar | Float64 128^3 | 3.577 ms | 2.025 ms | 1.630 ms | 1.420 ms | 3.332 ms | 1.082 ms | 536.115 μs | 273.273 μs | 407.644 μs | 2.306 ms | 1.276 ms | 129.981 μs |
| divergence! vec->scalar | Float64 256^3 | 31.003 ms | 21.358 ms | 17.413 ms | 15.758 ms | 27.143 ms | 11.131 ms | 10.313 ms | 10.251 ms | — | 7.090 ms | 2.351 ms | 747.328 μs |
| divergence! vec->scalar | Float64 512^3 | 241.030 ms | 164.044 ms | 135.853 ms | 126.447 ms | 211.819 ms | 95.607 ms | 92.961 ms | 93.073 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 407.318 μs | 162.684 μs | 86.541 μs | 56.911 μs | 436.625 μs | 141.861 μs | 71.341 μs | 40.820 μs | 103.111 μs | 344.869 μs | 1.091 ms | 67.061 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 5.666 ms | 2.475 ms | 1.254 ms | 702.418 μs | 4.946 ms | 2.045 ms | 1.020 ms | 527.695 μs | — | — | 1.116 ms | 100.051 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 45.296 ms | 18.812 ms | 10.055 ms | 8.952 ms | 39.536 ms | 16.116 ms | 8.119 ms | 4.262 ms | — | — | 2.159 ms | 416.114 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | 358.585 ms | 148.701 ms | 84.490 ms | 75.767 ms | 311.793 ms | 126.956 ms | 63.952 ms | 46.892 ms | — | — | 8.903 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 704.011 μs | 323.268 μs | 163.944 μs | 90.991 μs | 635.487 μs | 271.503 μs | 138.771 μs | 74.511 μs | — | — | 1.014 ms | 65.301 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 5.773 ms | 2.442 ms | 1.726 ms | 1.441 ms | 4.968 ms | 1.991 ms | 978.730 μs | 510.916 μs | — | — | 1.334 ms | 165.302 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 47.041 ms | 22.120 ms | 17.989 ms | 16.251 ms | 39.905 ms | 15.865 ms | 10.327 ms | 10.276 ms | — | — | 2.800 ms | 744.908 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | 371.499 ms | 168.086 ms | 138.832 ms | 128.627 ms | 311.790 ms | 123.354 ms | 93.777 ms | 93.248 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 697.877 μs | 309.333 μs | 158.013 μs | 89.429 μs | 636.917 μs | 257.132 μs | 131.121 μs | 70.881 μs | — | — | 1.080 ms | 76.001 μs |
| gradient! scalar->vec | Float32 128^3 | 3.126 ms | 1.674 ms | 877.614 μs | 514.574 μs | 1.956 ms | 973.410 μs | 489.695 μs | 255.323 μs | 560.525 μs | 2.377 ms | 1.059 ms | 85.561 μs |
| gradient! scalar->vec | Float32 256^3 | 25.011 ms | 14.353 ms | 13.055 ms | 12.729 ms | 15.628 ms | 7.811 ms | 5.648 ms | 5.642 ms | — | 7.929 ms | 1.690 ms | 441.394 μs |
| gradient! scalar->vec | Float32 512^3 | 199.337 ms | 116.955 ms | 111.158 ms | 107.159 ms | 124.510 ms | 66.098 ms | 63.587 ms | 64.217 ms | — | — | 4.503 ms | — |
| gradient! scalar->vec | Float32 64^3 | 392.515 μs | 215.930 μs | 106.683 μs | 58.804 μs | 248.293 μs | 125.971 μs | 63.910 μs | 34.800 μs | 133.261 μs | 1.681 ms | 1.092 ms | 56.630 μs |
| gradient! scalar->vec | Float64 128^3 | 3.352 ms | 2.822 ms | 2.461 ms | 2.283 ms | 2.068 ms | 990.610 μs | 488.485 μs | 255.383 μs | 605.225 μs | 2.717 ms | 1.291 ms | 159.132 μs |
| gradient! scalar->vec | Float64 256^3 | 30.957 ms | 28.470 ms | 27.121 ms | 26.391 ms | 20.256 ms | 14.697 ms | 13.993 ms | 14.102 ms | — | 10.338 ms | 2.570 ms | 806.689 μs |
| gradient! scalar->vec | Float64 512^3 | 234.597 ms | 227.254 ms | 221.627 ms | 215.372 ms | 154.953 ms | 128.469 ms | 127.527 ms | 128.432 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 361.664 μs | 189.697 μs | 97.431 μs | 59.724 μs | 262.483 μs | 125.061 μs | 63.261 μs | 34.170 μs | 153.172 μs | 1.872 ms | 1.067 ms | 68.831 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.366 ms | 2.237 ms | 1.410 ms | 1.200 ms | 3.376 ms | 1.688 ms | 854.709 μs | 443.815 μs | 1.480 ms | 4.174 ms | 1.185 ms | 95.961 μs |
| helmholtz! vec->vec | Float32 256^3 | 34.153 ms | 18.814 ms | 17.207 ms | 16.560 ms | 26.844 ms | 13.392 ms | 8.556 ms | 8.570 ms | — | 16.637 ms | 1.576 ms | 605.806 μs |
| helmholtz! vec->vec | Float32 512^3 | 272.421 ms | 152.183 ms | 144.369 ms | 137.372 ms | 215.412 ms | 108.302 ms | 82.730 ms | 83.839 ms | — | — | 6.527 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 550.289 μs | 284.226 μs | 145.361 μs | 78.711 μs | 450.615 μs | 227.562 μs | 115.182 μs | 60.821 μs | 286.333 μs | 1.935 ms | 1.087 ms | 68.261 μs |
| helmholtz! vec->vec | Float64 128^3 | 4.893 ms | 3.985 ms | 3.532 ms | 3.402 ms | 3.858 ms | 1.986 ms | 1.007 ms | 544.406 μs | 1.802 ms | 5.921 ms | 1.644 ms | 241.633 μs |
| helmholtz! vec->vec | Float64 256^3 | 45.002 ms | 38.172 ms | 35.478 ms | 34.248 ms | 34.872 ms | 20.390 ms | 19.339 ms | 19.560 ms | — | 18.240 ms | 3.761 ms | 1.407 ms |
| helmholtz! vec->vec | Float64 512^3 | 315.824 ms | 295.597 ms | 286.143 ms | 276.325 ms | 252.325 ms | 166.234 ms | 164.485 ms | 166.193 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 582.096 μs | 305.179 μs | 154.864 μs | 89.158 μs | 517.415 μs | 267.393 μs | 130.311 μs | 72.271 μs | 342.613 μs | 2.260 ms | 1.082 ms | 84.050 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 7.476 ms | 3.848 ms | 1.972 ms | 1.257 ms | 6.310 ms | 3.155 ms | 1.593 ms | 804.919 μs | — | — | 1.118 ms | 97.391 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 59.239 ms | 30.726 ms | 17.653 ms | 16.575 ms | 50.192 ms | 25.077 ms | 12.649 ms | 8.523 ms | — | — | 1.873 ms | 626.457 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | 469.969 ms | 242.465 ms | 146.286 ms | 137.596 ms | 401.643 ms | 200.976 ms | 105.731 ms | 83.127 ms | — | — | 7.994 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 944.376 μs | 493.213 μs | 247.877 μs | 135.415 μs | 831.928 μs | 421.624 μs | 211.122 μs | 110.141 μs | — | — | 1.110 ms | 71.080 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 7.923 ms | 4.200 ms | 3.595 ms | 3.432 ms | 6.782 ms | 3.586 ms | 1.739 ms | 919.680 μs | — | — | 1.486 ms | 310.773 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 71.545 ms | 39.009 ms | 35.692 ms | 34.390 ms | 55.724 ms | 28.070 ms | 19.338 ms | 19.384 ms | — | — | 3.998 ms | 1.639 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | 512.004 ms | 297.228 ms | 286.499 ms | 276.579 ms | 436.424 ms | 224.196 ms | 165.166 ms | 165.145 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 1.010 ms | 518.394 μs | 263.698 μs | 138.878 μs | 913.900 μs | 463.495 μs | 225.902 μs | 120.842 μs | — | — | 1.206 ms | 91.661 μs |
| inverse_laplacian! scalar | Float32 128^3 | 4.619 ms | 1.699 ms | 874.350 μs | 478.487 μs | 3.899 ms | 1.323 ms | 668.007 μs | 351.224 μs | — | — | 1.130 ms | 85.901 μs |
| inverse_laplacian! scalar | Float32 256^3 | 36.493 ms | 13.270 ms | 6.780 ms | 5.142 ms | 31.341 ms | 10.621 ms | 5.339 ms | 2.709 ms | — | — | 1.805 ms | 292.763 μs |
| inverse_laplacian! scalar | Float32 512^3 | 289.881 ms | 105.008 ms | 55.020 ms | 45.689 ms | 247.613 ms | 83.675 ms | 41.995 ms | 26.445 ms | — | — | 7.735 ms | — |
| inverse_laplacian! scalar | Float32 64^3 | 571.631 μs | 230.821 μs | 124.980 μs | 73.228 μs | 496.195 μs | 177.162 μs | 92.801 μs | 52.401 μs | — | — | 1.012 ms | 60.001 μs |
| inverse_laplacian! scalar | Float64 128^3 | 4.916 ms | 1.857 ms | 954.022 μs | 521.556 μs | 4.283 ms | 1.424 ms | 720.077 μs | 372.044 μs | — | — | 1.228 ms | 97.071 μs |
| inverse_laplacian! scalar | Float64 256^3 | 38.595 ms | 14.717 ms | 10.574 ms | 8.591 ms | 34.287 ms | 11.491 ms | 5.788 ms | 4.860 ms | — | — | 2.477 ms | 417.504 μs |
| inverse_laplacian! scalar | Float64 512^3 | 311.341 ms | 114.326 ms | 86.574 ms | 67.315 ms | 273.105 ms | 90.660 ms | 54.678 ms | 54.951 ms | — | — | — | — |
| inverse_laplacian! scalar | Float64 64^3 | 610.294 μs | 249.984 μs | 132.548 μs | 75.193 μs | 540.495 μs | 191.581 μs | 100.361 μs | 55.801 μs | — | — | 998.611 μs | 62.401 μs |
| laplacian! scalar | Float32 128^3 | 1.958 ms | 637.398 μs | 340.757 μs | 178.083 μs | 2.146 ms | 492.815 μs | 249.733 μs | 130.752 μs | 265.103 μs | 1.910 ms | 1.098 ms | 79.230 μs |
| laplacian! scalar | Float32 256^3 | 16.095 ms | 5.947 ms | 4.924 ms | 4.107 ms | 17.089 ms | 3.867 ms | 1.939 ms | 1.176 ms | — | 5.490 ms | 1.516 ms | 252.943 μs |
| laplacian! scalar | Float32 512^3 | 130.712 ms | 49.243 ms | 41.556 ms | 34.570 ms | 135.284 ms | 30.703 ms | 27.379 ms | 26.330 ms | — | — | 5.402 ms | — |
| laplacian! scalar | Float32 64^3 | 247.546 μs | 88.361 μs | 48.332 μs | 30.833 μs | 274.063 μs | 68.580 μs | 36.300 μs | 22.200 μs | 83.431 μs | 1.563 ms | 940.378 μs | 52.061 μs |
| laplacian! scalar | Float64 128^3 | 2.086 ms | 799.821 μs | 610.172 μs | 425.664 μs | 2.205 ms | 526.175 μs | 267.003 μs | 140.461 μs | 278.082 μs | 1.957 ms | 1.172 ms | 74.851 μs |
| laplacian! scalar | Float64 256^3 | 17.976 ms | 11.880 ms | 11.313 ms | 10.666 ms | 17.736 ms | 5.148 ms | 4.769 ms | 4.837 ms | — | 4.740 ms | 1.824 ms | 411.554 μs |
| laplacian! scalar | Float64 512^3 | 136.821 ms | 96.697 ms | 94.873 ms | 90.073 ms | 141.483 ms | 53.470 ms | 53.725 ms | 54.965 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 252.148 μs | 92.048 μs | 50.748 μs | 35.051 μs | 281.223 μs | 73.731 μs | 38.740 μs | 23.721 μs | 84.420 μs | 1.586 ms | 1.031 ms | 65.031 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 12.011 ms | 6.218 ms | 4.382 ms | 4.151 ms | 9.609 ms | 4.871 ms | 2.447 ms | 1.243 ms | — | — | 1.328 ms | 226.842 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 91.737 ms | 48.169 ms | 42.396 ms | 41.755 ms | 80.043 ms | 42.864 ms | 25.285 ms | 25.484 ms | — | — | 2.627 ms | 1.213 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | 719.902 ms | 388.330 ms | 348.213 ms | 336.925 ms | 649.413 ms | 329.518 ms | 208.750 ms | 198.615 ms | — | — | 14.648 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.439 ms | 735.446 μs | 376.005 μs | 199.969 μs | 1.213 ms | 621.856 μs | 310.833 μs | 158.652 μs | — | — | 1.168 ms | 69.811 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 13.391 ms | 10.959 ms | 9.649 ms | 9.488 ms | 10.644 ms | 5.712 ms | 3.769 ms | 3.752 ms | — | — | 1.640 ms | 356.693 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 115.709 ms | 91.065 ms | 86.479 ms | 84.782 ms | 85.169 ms | 52.461 ms | 48.928 ms | 49.421 ms | — | — | 4.482 ms | 2.294 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | 842.034 ms | 696.672 ms | 673.680 ms | 681.051 ms | 692.948 ms | 440.188 ms | 390.425 ms | 398.659 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.535 ms | 791.321 μs | 413.076 μs | 221.171 μs | 1.276 ms | 649.906 μs | 324.984 μs | 166.662 μs | — | — | 1.072 ms | 100.881 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.184 μs | 1.116 μs | 1.122 μs | 1.118 μs | 1.163 μs | 1.175 μs | 1.160 μs | 1.166 μs | 296.642 μs | 1.855 ms | 988.029 μs | 93.901 μs |
| assignment_window | Float32 256^3 | 2.182 μs | 2.182 μs | 2.189 μs | 2.200 μs | 2.217 μs | 2.237 μs | 2.225 μs | 2.227 μs | — | 3.952 ms | 1.086 ms | 93.822 μs |
| assignment_window | Float32 512^3 | 4.430 μs | 4.419 μs | 4.440 μs | 4.459 μs | 4.450 μs | 4.483 μs | 4.476 μs | 4.490 μs | — | — | 1.063 ms | — |
| assignment_window | Float32 64^3 | 604.128 ns | 590.983 ns | 609.251 ns | 601.374 ns | 606.085 ns | 609.949 ns | 606.520 ns | 605.688 ns | 138.651 μs | 1.640 ms | 1.045 ms | 95.041 μs |
| assignment_window | Float64 128^3 | 1.466 μs | 1.505 μs | 1.496 μs | 1.577 μs | 1.582 μs | 1.587 μs | 1.553 μs | 1.572 μs | 306.863 μs | 1.901 ms | 1.067 ms | 92.421 μs |
| assignment_window | Float64 256^3 | 3.065 μs | 3.143 μs | 3.116 μs | 3.315 μs | 3.123 μs | 3.110 μs | 3.113 μs | 3.112 μs | — | 4.237 ms | 1.121 ms | 106.021 μs |
| assignment_window | Float64 512^3 | 5.945 μs | 6.063 μs | 6.048 μs | 6.401 μs | 6.016 μs | 6.042 μs | 5.960 μs | 5.978 μs | — | — | — | — |
| assignment_window | Float64 64^3 | 734.540 ns | 743.932 ns | 799.793 ns | 786.742 ns | 861.754 ns | 825.141 ns | 821.481 ns | 825.190 ns | 141.232 μs | 1.542 ms | 998.034 μs | 89.011 μs |
| combine!∘kernel vector | Float32 128^3 | 4.733 ms | 2.219 ms | 1.598 ms | 1.471 ms | 3.148 ms | 1.547 ms | 774.478 μs | 406.874 μs | — | — | 1.248 ms | 135.661 μs |
| combine!∘kernel vector | Float32 256^3 | 31.065 ms | 20.832 ms | 19.500 ms | 18.608 ms | 25.200 ms | 12.635 ms | 9.904 ms | 9.869 ms | — | — | 1.956 ms | 921.623 μs |
| combine!∘kernel vector | Float32 512^3 | 263.209 ms | 173.203 ms | 161.672 ms | 153.536 ms | 241.726 ms | 101.986 ms | 92.582 ms | 92.954 ms | — | — | 8.998 ms | — |
| combine!∘kernel vector | Float32 64^3 | 490.575 μs | 278.176 μs | 136.540 μs | 74.747 μs | 418.605 μs | 207.312 μs | 106.431 μs | 55.391 μs | — | — | 986.036 μs | 66.600 μs |
| combine!∘kernel vector | Float64 128^3 | 5.425 ms | 4.648 ms | 4.138 ms | 3.926 ms | 3.710 ms | 2.066 ms | 1.098 ms | 746.598 μs | — | — | 1.327 ms | 287.253 μs |
| combine!∘kernel vector | Float64 256^3 | 48.876 ms | 43.187 ms | 40.859 ms | 38.569 ms | 33.977 ms | 23.030 ms | 21.974 ms | 22.132 ms | — | — | 3.016 ms | 1.802 ms |
| combine!∘kernel vector | Float64 512^3 | 355.482 ms | 337.734 ms | 321.947 ms | 308.026 ms | 245.246 ms | 187.574 ms | 182.715 ms | 183.714 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 518.029 μs | 280.676 μs | 141.916 μs | 84.508 μs | 387.474 μs | 228.693 μs | 114.901 μs | 62.821 μs | — | — | 1.114 ms | 83.211 μs |
| convolve! scalar | Float32 128^3 | 1.593 ms | 299.555 μs | 202.038 μs | 87.165 μs | 918.179 μs | 105.701 μs | 54.121 μs | 36.930 μs | 220.032 μs | 1.755 ms | 1.113 ms | 64.391 μs |
| convolve! scalar | Float32 256^3 | 13.168 ms | 7.734 ms | 7.298 ms | 6.742 ms | 7.560 ms | 2.888 ms | 2.671 ms | 2.731 ms | — | 3.659 ms | 1.533 ms | 313.183 μs |
| convolve! scalar | Float32 512^3 | 105.047 ms | 65.771 ms | 63.420 ms | 59.295 ms | 62.068 ms | 37.135 ms | 36.578 ms | 37.187 ms | — | — | 4.281 ms | — |
| convolve! scalar | Float32 64^3 | 196.941 μs | 26.366 μs | 21.237 μs | 13.663 μs | 117.701 μs | 16.250 μs | 9.280 μs | 7.367 μs | 78.951 μs | 1.480 ms | 954.742 μs | 51.760 μs |
| convolve! scalar | Float64 128^3 | 1.766 ms | 1.342 ms | 1.158 ms | 1.024 ms | 998.230 μs | 172.931 μs | 108.721 μs | 72.101 μs | 302.553 μs | 1.784 ms | 1.094 ms | 91.731 μs |
| convolve! scalar | Float64 256^3 | 17.950 ms | 16.185 ms | 15.215 ms | 14.239 ms | 10.978 ms | 7.904 ms | 7.615 ms | 7.743 ms | — | 4.442 ms | 1.948 ms | 578.596 μs |
| convolve! scalar | Float64 512^3 | 144.010 ms | 132.439 ms | 125.743 ms | 118.467 ms | 90.245 ms | 73.494 ms | 73.802 ms | 74.193 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 176.050 μs | 53.891 μs | 36.206 μs | 21.416 μs | 127.311 μs | 26.300 μs | 14.180 μs | 10.430 μs | 78.591 μs | 1.618 ms | 946.660 μs | 57.431 μs |
| convolve! vector | Float32 128^3 | 2.984 ms | 1.838 ms | 1.551 ms | 1.479 ms | 2.101 ms | 1.097 ms | 548.735 μs | 284.543 μs | 731.727 μs | 2.557 ms | 1.106 ms | 108.981 μs |
| convolve! vector | Float32 256^3 | 22.387 ms | 20.504 ms | 19.166 ms | 18.409 ms | 19.630 ms | 10.871 ms | 9.826 ms | 9.863 ms | — | 10.821 ms | 1.674 ms | 687.130 μs |
| convolve! vector | Float32 512^3 | 191.859 ms | 170.217 ms | 159.751 ms | 153.181 ms | 177.794 ms | 93.972 ms | 92.406 ms | 92.729 ms | — | — | 5.606 ms | — |
| convolve! vector | Float32 64^3 | 310.204 μs | 175.555 μs | 91.565 μs | 50.635 μs | 265.933 μs | 146.881 μs | 76.351 μs | 40.300 μs | 161.751 μs | 1.595 ms | 1.095 ms | 69.491 μs |
| convolve! vector | Float64 128^3 | 4.894 ms | 4.657 ms | 4.123 ms | 3.924 ms | 2.605 ms | 1.533 ms | 875.319 μs | 748.228 μs | 792.657 μs | 2.910 ms | 1.177 ms | 227.082 μs |
| convolve! vector | Float64 256^3 | 45.023 ms | 42.534 ms | 40.240 ms | 38.388 ms | 30.569 ms | 22.824 ms | 21.921 ms | 23.336 ms | — | 12.297 ms | 2.548 ms | 1.328 ms |
| convolve! vector | Float64 512^3 | 334.361 ms | 334.536 ms | 321.022 ms | 307.704 ms | 216.391 ms | 186.041 ms | 181.595 ms | 183.369 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 275.006 μs | 169.460 μs | 89.733 μs | 55.406 μs | 221.142 μs | 138.041 μs | 70.731 μs | 40.700 μs | 167.451 μs | 1.655 ms | 1.059 ms | 85.591 μs |
| convolve! vector ∘ radial    | Float32 128^3 | 4.137 ms | 2.168 ms | 1.467 ms | 1.230 ms | 2.501 ms | 1.248 ms | 621.806 μs | 320.224 μs | — | — | 1.405 ms | 136.492 μs |
| convolve! vector ∘ radial    | Float32 256^3 | 32.442 ms | 19.540 ms | 16.261 ms | 14.167 ms | 23.854 ms | 9.943 ms | 8.199 ms | 8.357 ms | — | — | 2.954 ms | 680.220 μs |
| convolve! vector ∘ radial    | Float32 512^3 | 260.754 ms | 153.051 ms | 125.871 ms | 105.766 ms | 163.709 ms | 85.687 ms | 81.600 ms | 82.263 ms | — | — | 14.831 ms | — |
| convolve! vector ∘ radial    | Float32 64^3 | 525.698 μs | 272.587 μs | 132.730 μs | 75.186 μs | 315.994 μs | 160.111 μs | 82.161 μs | 44.670 μs | — | — | 1.071 ms | 61.341 μs |
| convolve! vector ∘ radial    | Float64 128^3 | 5.089 ms | 4.032 ms | 3.543 ms | 2.914 ms | 2.881 ms | 1.456 ms | 725.047 μs | 408.544 μs | — | — | 1.342 ms | 199.642 μs |
| convolve! vector ∘ radial    | Float64 256^3 | 41.150 ms | 36.634 ms | 29.849 ms | 26.341 ms | 23.825 ms | 18.552 ms | 18.737 ms | 19.028 ms | — | — | 3.609 ms | 1.136 ms |
| convolve! vector ∘ radial    | Float64 512^3 | 328.914 ms | 292.288 ms | 227.544 ms | 198.790 ms | 190.450 ms | 162.437 ms | 159.924 ms | 163.249 ms | — | — | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | 532.804 μs | 275.934 μs | 146.401 μs | 94.811 μs | 355.124 μs | 174.721 μs | 89.451 μs | 49.610 μs | — | — | 1.101 ms | 72.201 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | 2.965 ms | 1.833 ms | 1.563 ms | 1.486 ms | 2.096 ms | 1.101 ms | 549.355 μs | 286.123 μs | — | — | 1.061 ms | 108.741 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | 22.549 ms | 20.741 ms | 19.339 ms | 18.401 ms | 19.571 ms | 10.801 ms | 9.825 ms | 9.827 ms | — | — | 1.633 ms | 691.667 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | 193.133 ms | 169.985 ms | 159.839 ms | 153.165 ms | 177.041 ms | 94.239 ms | 92.014 ms | 92.431 ms | — | — | 6.429 ms | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | 310.387 μs | 176.035 μs | 91.522 μs | 51.388 μs | 266.082 μs | 147.112 μs | 76.161 μs | 40.231 μs | — | — | 1.083 ms | 61.040 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | 4.923 ms | 4.608 ms | 4.180 ms | 3.932 ms | 2.623 ms | 1.537 ms | 884.199 μs | 741.488 μs | — | — | 1.243 ms | 229.042 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | 44.713 ms | 42.494 ms | 40.030 ms | 38.411 ms | 30.214 ms | 22.450 ms | 21.913 ms | 23.279 ms | — | — | 2.375 ms | 1.303 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | 333.016 ms | 334.888 ms | 320.659 ms | 307.456 ms | 213.402 ms | 184.492 ms | 181.668 ms | 183.153 ms | — | — | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | 276.289 μs | 168.856 μs | 88.106 μs | 52.225 μs | 220.563 μs | 135.471 μs | 70.301 μs | 40.491 μs | — | — | 894.897 μs | 68.241 μs |
| convolve! vector ∘ separable | Float32 128^3 | 6.760 ms | 3.455 ms | 1.754 ms | 1.213 ms | 4.679 ms | 2.342 ms | 1.170 ms | 595.136 μs | — | — | 1.378 ms | 134.182 μs |
| convolve! vector ∘ separable | Float32 256^3 | 53.473 ms | 27.624 ms | 17.239 ms | 13.202 ms | 37.212 ms | 18.637 ms | 9.368 ms | 8.430 ms | — | — | 2.994 ms | 696.639 μs |
| convolve! vector ∘ separable | Float32 512^3 | 426.551 ms | 218.832 ms | 136.861 ms | 106.705 ms | 296.229 ms | 148.024 ms | 82.468 ms | 82.506 ms | — | — | 15.064 ms | — |
| convolve! vector ∘ separable | Float32 64^3 | 842.577 μs | 435.665 μs | 225.713 μs | 118.591 μs | 588.226 μs | 297.183 μs | 150.231 μs | 77.750 μs | — | — | 1.140 ms | 58.331 μs |
| convolve! vector ∘ separable | Float64 128^3 | 6.753 ms | 4.128 ms | 3.389 ms | 2.475 ms | 3.944 ms | 1.977 ms | 1.002 ms | 508.775 μs | — | — | 1.656 ms | 273.733 μs |
| convolve! vector ∘ separable | Float64 256^3 | 53.841 ms | 36.812 ms | 29.162 ms | 23.952 ms | 32.684 ms | 19.102 ms | 18.945 ms | 19.230 ms | — | — | 5.249 ms | 1.686 ms |
| convolve! vector ∘ separable | Float64 512^3 | 428.037 ms | 295.548 ms | 232.862 ms | 189.892 ms | 261.127 ms | 162.535 ms | 160.190 ms | 163.937 ms | — | — | — | — |
| convolve! vector ∘ separable | Float64 64^3 | 808.651 μs | 436.674 μs | 215.832 μs | 120.351 μs | 494.465 μs | 247.843 μs | 125.981 μs | 66.391 μs | — | — | 1.148 ms | 86.011 μs |
| convolve! vector ∘ stored    | Float32 128^3 | 2.991 ms | 1.833 ms | 1.554 ms | 1.483 ms | 2.101 ms | 1.102 ms | 548.946 μs | 288.073 μs | — | — | 1.071 ms | 102.921 μs |
| convolve! vector ∘ stored    | Float32 256^3 | 22.564 ms | 20.516 ms | 19.219 ms | 18.417 ms | 19.500 ms | 10.879 ms | 9.845 ms | 9.890 ms | — | — | 1.633 ms | 687.529 μs |
| convolve! vector ∘ stored    | Float32 512^3 | 193.408 ms | 169.825 ms | 159.741 ms | 153.249 ms | 177.987 ms | 94.174 ms | 92.411 ms | 92.678 ms | — | — | 6.387 ms | — |
| convolve! vector ∘ stored    | Float32 64^3 | 309.962 μs | 178.565 μs | 91.368 μs | 54.553 μs | 268.863 μs | 147.491 μs | 76.071 μs | 40.430 μs | — | — | 1.011 ms | 65.630 μs |
| convolve! vector ∘ stored    | Float64 128^3 | 4.906 ms | 4.598 ms | 4.136 ms | 3.929 ms | 2.631 ms | 1.548 ms | 890.159 μs | 754.868 μs | — | — | 1.273 ms | 224.422 μs |
| convolve! vector ∘ stored    | Float64 256^3 | 44.753 ms | 42.666 ms | 40.028 ms | 38.471 ms | 30.567 ms | 22.831 ms | 21.923 ms | 22.074 ms | — | — | 2.478 ms | 1.310 ms |
| convolve! vector ∘ stored    | Float64 512^3 | 330.158 ms | 334.980 ms | 320.788 ms | 307.347 ms | 216.348 ms | 186.027 ms | 181.804 ms | 183.330 ms | — | — | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | 274.539 μs | 164.133 μs | 88.964 μs | 60.719 μs | 220.662 μs | 137.231 μs | 71.851 μs | 40.251 μs | — | — | 1.131 ms | 87.921 μs |
| exponential_convolve! scalar | Float32 128^3 | 6.109 ms | 2.702 ms | 1.361 ms | 722.348 μs | 4.991 ms | 2.116 ms | 1.064 ms | 540.806 μs | — | — | 1.095 ms | 70.450 μs |
| exponential_convolve! scalar | Float32 256^3 | 48.311 ms | 21.234 ms | 10.718 ms | 6.141 ms | 39.666 ms | 16.613 ms | 8.306 ms | 4.223 ms | — | — | 1.573 ms | 256.214 μs |
| exponential_convolve! scalar | Float32 512^3 | 384.722 ms | 167.829 ms | 84.785 ms | 50.497 ms | 316.360 ms | 131.459 ms | 67.981 ms | 34.184 ms | — | — | 6.184 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 762.967 μs | 349.962 μs | 179.859 μs | 101.305 μs | 640.356 μs | 279.823 μs | 144.401 μs | 78.171 μs | — | — | 1.062 ms | 57.980 μs |
| exponential_convolve! scalar | Float64 128^3 | 5.784 ms | 2.553 ms | 1.331 ms | 835.192 μs | 5.534 ms | 2.380 ms | 1.196 ms | 612.507 μs | — | — | 1.279 ms | 126.411 μs |
| exponential_convolve! scalar | Float64 256^3 | 45.717 ms | 20.058 ms | 12.133 ms | 10.752 ms | 43.961 ms | 18.803 ms | 9.429 ms | 4.991 ms | — | — | 2.599 ms | 644.777 μs |
| exponential_convolve! scalar | Float64 512^3 | 364.009 ms | 160.020 ms | 97.219 ms | 90.369 ms | 348.563 ms | 149.341 ms | 79.376 ms | 54.935 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 719.321 μs | 328.503 μs | 170.993 μs | 103.498 μs | 694.677 μs | 313.213 μs | 158.272 μs | 86.021 μs | — | — | 1.078 ms | 64.240 μs |
| exponential_convolve! vector | Float32 128^3 | 20.248 ms | 9.678 ms | 4.892 ms | 2.629 ms | 16.520 ms | 7.665 ms | 3.842 ms | 1.959 ms | — | — | 569.601 μs | 137.112 μs |
| exponential_convolve! vector | Float32 256^3 | 160.278 ms | 76.157 ms | 38.541 ms | 22.375 ms | 130.345 ms | 60.344 ms | 30.346 ms | 15.587 ms | — | — | 3.041 ms | 695.507 μs |
| exponential_convolve! vector | Float32 512^3 | 1.274 s | 603.661 ms | 304.604 ms | 182.939 ms | 1.038 s | 477.842 ms | 241.243 ms | 126.168 ms | — | — | 14.879 ms | — |
| exponential_convolve! vector | Float32 64^3 | 2.542 ms | 1.233 ms | 639.809 μs | 332.578 μs | 2.138 ms | 1.031 ms | 500.135 μs | 261.863 μs | — | — | 1.107 ms | 62.221 μs |
| exponential_convolve! vector | Float64 128^3 | 19.539 ms | 9.328 ms | 4.822 ms | 3.554 ms | 18.438 ms | 8.627 ms | 4.330 ms | 2.204 ms | — | — | 1.824 ms | 287.892 μs |
| exponential_convolve! vector | Float64 256^3 | 154.206 ms | 72.909 ms | 38.108 ms | 33.695 ms | 148.736 ms | 67.971 ms | 34.535 ms | 19.334 ms | — | — | 5.702 ms | 1.773 ms |
| exponential_convolve! vector | Float64 512^3 | 1.226 s | 579.498 ms | 304.348 ms | 273.431 ms | 1.157 s | 536.451 ms | 272.619 ms | 164.043 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.475 ms | 1.167 ms | 606.307 μs | 324.223 μs | 2.324 ms | 1.091 ms | 552.276 μs | 283.844 μs | — | — | 1.031 ms | 83.771 μs |
| inv separable | Float32 128^3 | 951.739 ns | 950.238 ns | 952.333 ns | 966.625 ns | 773.518 ns | 778.952 ns | 767.890 ns | 759.288 ns | — | — | 1.079 ms | 149.721 μs |
| inv separable | Float32 256^3 | 1.964 μs | 1.958 μs | 1.961 μs | 1.977 μs | 1.549 μs | 1.564 μs | 1.573 μs | 1.560 μs | — | — | 1.001 ms | 154.762 μs |
| inv separable | Float32 512^3 | 3.819 μs | 3.800 μs | 3.825 μs | 3.861 μs | 3.001 μs | 3.025 μs | 3.020 μs | 3.075 μs | — | — | 1.713 ms | — |
| inv separable | Float32 64^3 | 506.674 ns | 505.212 ns | 506.068 ns | 509.042 ns | 411.955 ns | 412.116 ns | 412.719 ns | 408.497 ns | — | — | 1.086 ms | 146.512 μs |
| inv separable | Float64 128^3 | 1.096 μs | 1.129 μs | 1.097 μs | 1.132 μs | 1.057 μs | 1.086 μs | 1.078 μs | 1.051 μs | — | — | 1.043 ms | 149.251 μs |
| inv separable | Float64 256^3 | 2.143 μs | 2.425 μs | 2.151 μs | 2.153 μs | 2.022 μs | 2.053 μs | 2.143 μs | 2.084 μs | — | — | 978.101 μs | 206.633 μs |
| inv separable | Float64 512^3 | 4.041 μs | 4.067 μs | 4.037 μs | 4.086 μs | 3.976 μs | 3.974 μs | 3.986 μs | 4.016 μs | — | — | — | — |
| inv separable | Float64 64^3 | 530.085 ns | 531.698 ns | 530.872 ns | 533.005 ns | 518.696 ns | 525.349 ns | 574.614 ns | 524.979 ns | — | — | 1.013 ms | 149.851 μs |
| materialize_kernel radial | Float32 128^3 | 1.380 ms | 607.802 μs | 408.922 μs | 232.532 μs | 1.129 ms | 351.943 μs | 178.982 μs | 93.851 μs | — | — | 1.191 ms | 94.411 μs |
| materialize_kernel radial | Float32 256^3 | 11.162 ms | 4.595 ms | 3.615 ms | 2.618 ms | 8.904 ms | 2.760 ms | 1.972 ms | 1.824 ms | — | — | 1.639 ms | 217.823 μs |
| materialize_kernel radial | Float32 512^3 | 88.854 ms | 36.249 ms | 28.671 ms | 21.990 ms | 70.810 ms | 22.141 ms | 17.180 ms | 17.528 ms | — | — | 6.042 ms | — |
| materialize_kernel radial | Float32 64^3 | 174.953 μs | 85.421 μs | 40.399 μs | 31.178 μs | 145.601 μs | 47.801 μs | 26.460 μs | 15.700 μs | — | — | 1.053 ms | 71.981 μs |
| materialize_kernel radial | Float64 128^3 | 1.481 ms | 916.003 μs | 693.147 μs | 440.954 μs | 1.174 ms | 380.304 μs | 264.922 μs | 253.083 μs | — | — | 1.206 ms | 89.381 μs |
| materialize_kernel radial | Float64 256^3 | 11.692 ms | 7.861 ms | 5.675 ms | 5.391 ms | 9.313 ms | 4.106 ms | 3.878 ms | 3.859 ms | — | — | 1.800 ms | 255.453 μs |
| materialize_kernel radial | Float64 512^3 | 93.204 ms | 142.965 ms | 76.707 ms | 47.893 ms | 74.489 ms | 91.941 ms | 52.873 ms | 35.766 ms | — | — | — | — |
| materialize_kernel radial | Float64 64^3 | 177.126 μs | 71.706 μs | 53.233 μs | 35.568 μs | 151.121 μs | 48.020 μs | 25.440 μs | 15.910 μs | — | — | 1.071 ms | 76.121 μs |
| materialize_kernel separable | Float32 128^3 | 1.794 ms | 782.748 μs | 448.019 μs | 322.260 μs | 1.533 ms | 445.595 μs | 225.982 μs | 116.912 μs | — | — | 1.180 ms | 78.370 μs |
| materialize_kernel separable | Float32 256^3 | 14.330 ms | 6.139 ms | 3.949 ms | 3.060 ms | 12.126 ms | 3.495 ms | 2.008 ms | 1.788 ms | — | — | 1.617 ms | 231.963 μs |
| materialize_kernel separable | Float32 512^3 | 114.889 ms | 49.178 ms | 31.341 ms | 23.919 ms | 96.549 ms | 27.885 ms | 18.950 ms | 17.906 ms | — | — | 5.269 ms | — |
| materialize_kernel separable | Float32 64^3 | 227.903 μs | 102.342 μs | 54.917 μs | 34.716 μs | 196.132 μs | 60.220 μs | 32.000 μs | 18.761 μs | — | — | 1.058 ms | 70.721 μs |
| materialize_kernel separable | Float64 128^3 | 1.778 ms | 958.451 μs | 773.722 μs | 503.520 μs | 1.447 ms | 456.985 μs | 296.063 μs | 215.432 μs | — | — | 1.116 ms | 113.981 μs |
| materialize_kernel separable | Float64 256^3 | 14.237 ms | 7.910 ms | 5.980 ms | 5.604 ms | 11.432 ms | 4.020 ms | 3.946 ms | 4.021 ms | — | — | 2.239 ms | 415.054 μs |
| materialize_kernel separable | Float64 512^3 | 114.959 ms | 63.370 ms | 82.029 ms | 50.289 ms | 90.986 ms | 104.961 ms | 62.488 ms | 43.728 ms | — | — | — | — |
| materialize_kernel separable | Float64 64^3 | 224.892 μs | 101.110 μs | 56.287 μs | 51.687 μs | 186.292 μs | 61.030 μs | 32.261 μs | 19.281 μs | — | — | 1.116 ms | 73.281 μs |
| radial_kernel | Float32 128^3 | 3.451 ns | 2.814 ns | 2.817 ns | 2.817 ns | 3.200 ns | 3.170 ns | 3.180 ns | 3.050 ns | — | — | 1.024 μs | 1.496 μs |
| radial_kernel | Float32 256^3 | 2.814 ns | 2.814 ns | 2.817 ns | 2.815 ns | 3.180 ns | 3.180 ns | 3.180 ns | 3.050 ns | — | — | 984.750 ns | 1.943 μs |
| radial_kernel | Float32 512^3 | 2.814 ns | 2.815 ns | 2.817 ns | 2.820 ns | 3.190 ns | 3.170 ns | 3.180 ns | 3.050 ns | — | — | 1.034 μs | — |
| radial_kernel | Float32 64^3 | 2.818 ns | 2.815 ns | 2.816 ns | 2.816 ns | 3.200 ns | 3.170 ns | 3.180 ns | 3.040 ns | — | — | 886.875 ns | 2.190 μs |
| radial_kernel | Float64 128^3 | 3.014 ns | 3.014 ns | 3.017 ns | 3.013 ns | 3.200 ns | 3.170 ns | 3.180 ns | 3.170 ns | — | — | 1.056 μs | 2.004 μs |
| radial_kernel | Float64 256^3 | 3.015 ns | 3.014 ns | 3.020 ns | 3.014 ns | 3.200 ns | 3.160 ns | 3.160 ns | 3.150 ns | — | — | 822.111 ns | 1.350 μs |
| radial_kernel | Float64 512^3 | 3.015 ns | 3.014 ns | 3.016 ns | 3.013 ns | 3.190 ns | 3.170 ns | 3.170 ns | 3.170 ns | — | — | — | — |
| radial_kernel | Float64 64^3 | 3.014 ns | 3.014 ns | 3.016 ns | 3.013 ns | 3.200 ns | 3.170 ns | 3.170 ns | 3.150 ns | — | — | 1.008 μs | 1.294 μs |
| spectral_band | Float32 128^3 | 12.428 ns | 10.398 ns | 11.325 ns | 11.830 ns | 9.049 ns | 9.650 ns | 10.420 ns | 8.769 ns | 334.154 μs | 2.050 ms | 916.375 ns | 1.520 μs |
| spectral_band | Float32 256^3 | 12.430 ns | 10.404 ns | 11.311 ns | 11.829 ns | 9.039 ns | 9.670 ns | 10.430 ns | 8.779 ns | — | 6.344 ms | 935.875 ns | 1.469 μs |
| spectral_band | Float32 512^3 | 12.417 ns | 10.391 ns | 11.282 ns | 11.829 ns | 9.039 ns | 9.660 ns | 10.430 ns | 8.769 ns | — | — | 1.087 μs | — |
| spectral_band | Float32 64^3 | 12.417 ns | 10.359 ns | 11.441 ns | 11.831 ns | 9.039 ns | 9.670 ns | 10.421 ns | 8.769 ns | 106.071 μs | 1.537 ms | 953.250 ns | 2.603 μs |
| spectral_band | Float64 128^3 | 11.688 ns | 10.924 ns | 11.498 ns | 11.851 ns | 10.280 ns | 10.080 ns | 10.100 ns | 9.770 ns | 361.113 μs | 2.105 ms | 1.070 μs | 1.339 μs |
| spectral_band | Float64 256^3 | 11.688 ns | 10.916 ns | 11.493 ns | 11.852 ns | 10.260 ns | 10.090 ns | 10.080 ns | 9.770 ns | — | 5.611 ms | 979.625 ns | 2.402 μs |
| spectral_band | Float64 512^3 | 11.668 ns | 10.915 ns | 11.499 ns | 11.855 ns | 10.270 ns | 10.090 ns | 10.100 ns | 9.820 ns | — | — | — | — |
| spectral_band | Float64 64^3 | 11.686 ns | 10.913 ns | 11.498 ns | 11.847 ns | 10.260 ns | 10.090 ns | 10.100 ns | 9.760 ns | 110.411 μs | 1.651 ms | 1.048 μs | 1.780 μs |
| spectral_cutoff | Float32 128^3 | 11.711 ns | 10.366 ns | 10.675 ns | 11.023 ns | 9.069 ns | 10.591 ns | 10.480 ns | 8.959 ns | 331.623 μs | 2.046 ms | 1.129 μs | 1.321 μs |
| spectral_cutoff | Float32 256^3 | 11.704 ns | 10.550 ns | 10.680 ns | 11.023 ns | 9.069 ns | 10.571 ns | 10.501 ns | 8.949 ns | — | 5.403 ms | 1.164 μs | 1.433 μs |
| spectral_cutoff | Float32 512^3 | 11.706 ns | 10.368 ns | 10.676 ns | 11.021 ns | 9.059 ns | 10.601 ns | 10.490 ns | 8.949 ns | — | — | 1.013 μs | — |
| spectral_cutoff | Float32 64^3 | 11.714 ns | 10.358 ns | 10.668 ns | 11.022 ns | 9.059 ns | 10.631 ns | 10.480 ns | 8.949 ns | 108.881 μs | 1.625 ms | 1.011 μs | 2.207 μs |
| spectral_cutoff | Float64 128^3 | 11.674 ns | 10.926 ns | 11.456 ns | 11.642 ns | 9.369 ns | 10.060 ns | 10.200 ns | 9.149 ns | 351.793 μs | 2.120 ms | 1.109 μs | 1.588 μs |
| spectral_cutoff | Float64 256^3 | 11.669 ns | 10.909 ns | 11.461 ns | 11.648 ns | 9.379 ns | 10.060 ns | 10.270 ns | 9.179 ns | — | 5.621 ms | 997.875 ns | 1.566 μs |
| spectral_cutoff | Float64 512^3 | 11.673 ns | 10.931 ns | 11.460 ns | 11.644 ns | 9.360 ns | 10.060 ns | 10.290 ns | 9.179 ns | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 11.670 ns | 10.891 ns | 11.469 ns | 11.642 ns | 9.379 ns | 10.050 ns | 10.260 ns | 9.159 ns | 117.711 μs | 1.647 ms | 945.500 ns | 1.813 μs |
| squared_wavenumber_field | Float32 128^3 | — | — | — | — | — | — | — | — | 262.463 μs | 1.824 ms | — | — |
| squared_wavenumber_field | Float32 256^3 | — | — | — | — | — | — | — | — | — | 3.812 ms | — | — |
| squared_wavenumber_field | Float32 64^3 | — | — | — | — | — | — | — | — | 91.321 μs | 1.517 ms | — | — |
| squared_wavenumber_field | Float64 128^3 | — | — | — | — | — | — | — | — | 264.163 μs | 1.805 ms | — | — |
| squared_wavenumber_field | Float64 256^3 | — | — | — | — | — | — | — | — | — | 4.151 ms | — | — |
| squared_wavenumber_field | Float64 64^3 | — | — | — | — | — | — | — | — | 88.931 μs | 1.612 ms | — | — |
| translation_kernel | Float32 128^3 | 1.837 μs | 1.801 μs | 1.813 μs | 1.805 μs | 1.411 μs | 1.421 μs | 1.418 μs | 1.417 μs | — | — | 1.099 ms | 80.071 μs |
| translation_kernel | Float32 256^3 | 3.550 μs | 3.551 μs | 3.571 μs | 3.558 μs | 2.727 μs | 2.748 μs | 2.728 μs | 2.731 μs | — | — | 919.962 μs | 72.811 μs |
| translation_kernel | Float32 512^3 | 6.921 μs | 6.928 μs | 6.938 μs | 6.920 μs | 5.317 μs | 5.309 μs | 5.290 μs | 5.309 μs | — | — | 1.661 ms | — |
| translation_kernel | Float32 64^3 | 898.475 ns | 898.286 ns | 908.450 ns | 900.683 ns | 740.333 ns | 747.581 ns | 738.728 ns | 742.808 ns | — | — | 929.542 μs | 74.390 μs |
| translation_kernel | Float64 128^3 | 2.032 μs | 2.041 μs | 2.035 μs | 2.149 μs | 1.846 μs | 1.854 μs | 1.836 μs | 1.818 μs | — | — | 1.099 ms | 78.341 μs |
| translation_kernel | Float64 256^3 | 3.872 μs | 3.864 μs | 3.868 μs | 4.096 μs | 3.481 μs | 3.501 μs | 3.501 μs | 3.489 μs | — | — | 1.091 ms | 90.141 μs |
| translation_kernel | Float64 512^3 | 7.391 μs | 7.417 μs | 7.390 μs | 7.712 μs | 6.897 μs | 6.880 μs | 6.800 μs | 6.820 μs | — | — | — | — |
| translation_kernel | Float64 64^3 | 1.018 μs | 1.019 μs | 1.019 μs | 1.071 μs | 940.357 ns | 941.667 ns | 930.032 ns | 933.483 ns | — | — | 1.031 ms | 81.460 μs |
| translation_kernel! | Float32 128^3 | 1.775 μs | 1.757 μs | 1.775 μs | 1.761 μs | 1.387 μs | 1.367 μs | 1.369 μs | 1.367 μs | — | — | 336.372 μs | 62.370 μs |
| translation_kernel! | Float32 256^3 | 3.433 μs | 3.411 μs | 3.421 μs | 3.430 μs | 2.612 μs | 2.616 μs | 2.616 μs | 2.611 μs | — | — | 884.876 μs | 62.881 μs |
| translation_kernel! | Float32 512^3 | 6.790 μs | 6.763 μs | 6.760 μs | 6.778 μs | 5.117 μs | 5.117 μs | 5.108 μs | 5.110 μs | — | — | 1.777 ms | — |
| translation_kernel! | Float32 64^3 | 855.857 ns | 858.097 ns | 856.365 ns | 856.349 ns | 698.618 ns | 700.979 ns | 699.382 ns | 699.731 ns | — | — | 1.069 ms | 73.941 μs |
| translation_kernel! | Float64 128^3 | 1.869 μs | 1.861 μs | 1.869 μs | 1.896 μs | 1.702 μs | 1.697 μs | 1.698 μs | 1.698 μs | — | — | 975.733 μs | 67.221 μs |
| translation_kernel! | Float64 256^3 | 3.619 μs | 3.666 μs | 3.606 μs | 3.691 μs | 3.265 μs | 3.244 μs | 3.243 μs | 3.259 μs | — | — | 1.098 ms | 72.810 μs |
| translation_kernel! | Float64 512^3 | 7.133 μs | 7.091 μs | 7.125 μs | 7.262 μs | 6.416 μs | 6.352 μs | 6.358 μs | 6.428 μs | — | — | — | — |
| translation_kernel! | Float64 64^3 | 961.850 ns | 963.632 ns | 960.789 ns | 984.600 ns | 882.308 ns | 880.196 ns | 878.113 ns | 877.222 ns | — | — | 1.087 ms | 63.141 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.523 ms | 13.706 ms | 7.329 ms | 4.417 ms | 20.912 ms | 11.048 ms | 5.914 ms | 3.413 ms | 2.280 ms | 4.864 ms | 1.584 ms | 211.552 μs |
| anterpolate! CatmullRom | Float32 256^3 | 392.571 ms | 204.137 ms | 108.428 ms | 67.165 ms | 175.213 ms | 89.919 ms | 45.737 ms | 23.771 ms | — | 17.932 ms | 3.927 ms | 2.905 ms |
| anterpolate! CatmullRom | Float32 512^3 | 3.899 s | 2.043 s | 1.152 s | 802.658 ms | 2.986 s | 1.528 s | 788.684 ms | 435.002 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.184 ms | 1.886 ms | 1.209 ms | 858.655 μs | 2.513 ms | 1.459 ms | 942.559 μs | 654.158 μs | 116.972 μs | 2.057 ms | 1.207 ms | 103.811 μs |
| anterpolate! CatmullRom | Float64 128^3 | 28.517 ms | 14.544 ms | 7.615 ms | 4.620 ms | 22.054 ms | 11.577 ms | 6.134 ms | 3.552 ms | 2.691 ms | 4.862 ms | 1.713 ms | 232.732 μs |
| anterpolate! CatmullRom | Float64 256^3 | 515.747 ms | 260.488 ms | 147.343 ms | 103.501 ms | 263.718 ms | 130.823 ms | 68.642 ms | 35.866 ms | — | 19.810 ms | 5.099 ms | 4.674 ms |
| anterpolate! CatmullRom | Float64 512^3 | 4.975 s | 2.629 s | 1.421 s | 881.899 ms | 3.469 s | 1.771 s | 959.186 ms | 533.733 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.273 ms | 1.912 ms | 1.242 ms | 897.872 μs | 2.529 ms | 1.497 ms | 964.220 μs | 694.778 μs | 185.312 μs | 2.004 ms | 1.357 ms | 125.271 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 197.640 ms | 100.081 ms | 50.847 ms | 28.541 ms | 159.823 ms | 80.435 ms | 40.794 ms | 21.754 ms | 12.241 ms | 15.478 ms | 4.137 ms | 1.008 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.313 s | 1.165 s | 669.872 ms | 483.110 ms | 1.285 s | 644.944 ms | 322.793 ms | 162.049 ms | — | 48.567 ms | 18.572 ms | 15.005 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | 21.687 s | 11.570 s | 6.858 s | 5.090 s | 11.781 s | 6.014 s | 3.044 s | 1.640 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.886 ms | 13.323 ms | 8.134 ms | 5.592 ms | 19.845 ms | 10.595 ms | 6.439 ms | 4.332 ms | 486.825 μs | 5.959 ms | 2.096 ms | 331.873 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 203.551 ms | 105.091 ms | 52.715 ms | 29.850 ms | 160.375 ms | 80.608 ms | 40.553 ms | 21.610 ms | 13.808 ms | 16.564 ms | 5.114 ms | 1.167 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.781 s | 1.392 s | 837.619 ms | 617.127 ms | 1.397 s | 701.875 ms | 355.192 ms | 179.393 ms | — | 66.043 ms | 28.540 ms | 24.277 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | 23.251 s | 12.461 s | 7.362 s | 5.495 s | 12.935 s | 6.567 s | 3.444 s | 2.239 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.346 ms | 13.244 ms | 8.209 ms | 5.637 ms | 19.908 ms | 10.742 ms | 6.589 ms | 4.422 ms | 825.268 μs | 5.503 ms | 2.627 ms | 341.853 μs |
| anterpolate! NUFFT | Float32 128^3 | 396.778 ms | 226.554 ms | 136.043 ms | 108.198 ms | 354.912 ms | 179.100 ms | 99.144 ms | 70.032 ms | 20.177 ms | 18.762 ms | 5.625 ms | 2.807 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.215 s | 2.310 s | 1.384 s | 1.018 s | 3.775 s | 1.865 s | 1.115 s | 600.033 ms | — | 120.799 ms | 33.009 ms | 28.629 ms |
| anterpolate! NUFFT | Float32 512^3 | 38.579 s | 21.459 s | 12.714 s | 9.095 s | 31.266 s | 16.422 s | 9.091 s | 5.565 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 31.561 ms | 18.156 ms | 11.315 ms | 8.234 ms | 27.034 ms | 14.278 ms | 8.606 ms | 5.963 ms | 1.989 ms | 6.296 ms | 2.756 ms | 448.185 μs |
| anterpolate! NUFFT | Float64 128^3 | 515.978 ms | 298.422 ms | 216.821 ms | 176.299 ms | 424.117 ms | 240.202 ms | 124.203 ms | 90.491 ms | 30.358 ms | 22.503 ms | 10.087 ms | 6.578 ms |
| anterpolate! NUFFT | Float64 256^3 | 4.964 s | 2.890 s | 1.931 s | 1.565 s | 3.631 s | 2.049 s | 1.237 s | 885.952 ms | — | 160.735 ms | 71.336 ms | 58.701 ms |
| anterpolate! NUFFT | Float64 512^3 | 44.022 s | 25.243 s | 16.235 s | 12.790 s | 40.189 s | 22.106 s | 12.844 s | 8.349 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 36.987 ms | 21.460 ms | 14.337 ms | 10.866 ms | 33.229 ms | 17.929 ms | 10.768 ms | 7.422 ms | 3.892 ms | 8.203 ms | 3.680 ms | 844.939 μs |
| anterpolate! trilinear | Float32 128^3 | 4.695 ms | 2.261 ms | 1.352 ms | 881.126 μs | 4.768 ms | 2.531 ms | 1.436 ms | 861.569 μs | 460.884 μs | 2.018 ms | 1.128 ms | 77.391 μs |
| anterpolate! trilinear | Float32 256^3 | 80.940 ms | 44.334 ms | 25.586 ms | 20.086 ms | 42.961 ms | 22.643 ms | 11.942 ms | 6.548 ms | — | 6.631 ms | 1.650 ms | 740.780 μs |
| anterpolate! trilinear | Float32 512^3 | 730.809 ms | 400.257 ms | 248.098 ms | 201.541 ms | 752.687 ms | 401.125 ms | 205.681 ms | 120.364 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 485.517 μs | 322.905 μs | 208.906 μs | 161.045 μs | 369.244 μs | 228.092 μs | 167.742 μs | 127.042 μs | 70.080 μs | 1.565 ms | 898.799 μs | 66.331 μs |
| anterpolate! trilinear | Float64 128^3 | 5.140 ms | 2.667 ms | 1.561 ms | 1.087 ms | 5.987 ms | 3.404 ms | 1.871 ms | 1.171 ms | 596.666 μs | 1.980 ms | 1.232 ms | 95.391 μs |
| anterpolate! trilinear | Float64 256^3 | 93.226 ms | 51.331 ms | 33.258 ms | 27.126 ms | 72.130 ms | 36.849 ms | 19.998 ms | 11.359 ms | — | 6.838 ms | 1.853 ms | 1.121 ms |
| anterpolate! trilinear | Float64 512^3 | 788.544 ms | 452.004 ms | 270.764 ms | 210.306 ms | 797.636 ms | 405.638 ms | 228.511 ms | 129.219 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 522.769 μs | 338.908 μs | 241.823 μs | 191.637 μs | 381.854 μs | 238.882 μs | 178.662 μs | 133.821 μs | 83.721 μs | 1.554 ms | 1.084 ms | 75.531 μs |
| interpolate! CatmullRom | Float32 128^3 | 11.612 ms | 5.895 ms | 2.955 ms | 1.650 ms | 5.425 ms | 2.762 ms | 1.392 ms | 738.058 μs | 972.889 μs | 3.140 ms | 1.314 ms | 127.071 μs |
| interpolate! CatmullRom | Float32 256^3 | 271.654 ms | 139.395 ms | 75.000 ms | 47.020 ms | 56.253 ms | 29.997 ms | 14.577 ms | 7.106 ms | — | 14.577 ms | 2.670 ms | 877.042 μs |
| interpolate! CatmullRom | Float32 512^3 | 2.493 s | 1.307 s | 770.720 ms | 536.386 ms | 1.864 s | 955.565 ms | 471.362 ms | 262.337 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.311 ms | 708.196 μs | 429.733 μs | 300.112 μs | 615.876 μs | 331.993 μs | 199.181 μs | 135.851 μs | 101.321 μs | 1.724 ms | 984.295 μs | 79.591 μs |
| interpolate! CatmullRom | Float64 128^3 | 12.345 ms | 6.808 ms | 3.482 ms | 1.941 ms | 5.656 ms | 2.871 ms | 1.443 ms | 771.479 μs | 1.411 ms | 2.789 ms | 1.357 ms | 188.842 μs |
| interpolate! CatmullRom | Float64 256^3 | 312.744 ms | 154.605 ms | 88.131 ms | 60.708 ms | 151.427 ms | 71.177 ms | 37.894 ms | 19.384 ms | — | 12.939 ms | 2.974 ms | 1.709 ms |
| interpolate! CatmullRom | Float64 512^3 | 2.726 s | 1.439 s | 765.411 ms | 487.613 ms | 2.133 s | 1.059 s | 564.553 ms | 306.763 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.360 ms | 739.388 μs | 449.929 μs | 314.905 μs | 664.747 μs | 354.734 μs | 216.343 μs | 144.432 μs | 166.201 μs | 1.759 ms | 1.296 ms | 115.651 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.947 ms | 37.408 ms | 18.912 ms | 10.471 ms | 42.292 ms | 21.290 ms | 10.688 ms | 5.675 ms | 5.370 ms | 14.027 ms | 2.860 ms | 480.305 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.512 s | 784.647 ms | 496.217 ms | 326.458 ms | 347.967 ms | 179.280 ms | 88.337 ms | 44.311 ms | — | 30.216 ms | 11.918 ms | 4.720 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | 15.272 s | 8.498 s | 5.646 s | 3.875 s | 5.375 s | 2.949 s | 1.541 s | 875.888 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.741 ms | 4.700 ms | 2.857 ms | 1.950 ms | 5.069 ms | 2.674 ms | 1.607 ms | 1.079 ms | 688.416 μs | 3.166 ms | 1.709 ms | 276.323 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 78.951 ms | 42.466 ms | 21.810 ms | 12.118 ms | 41.761 ms | 20.951 ms | 10.497 ms | 5.527 ms | 8.105 ms | 9.517 ms | 3.251 ms | 834.399 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.986 s | 993.830 ms | 653.060 ms | 434.240 ms | 584.489 ms | 287.259 ms | 149.874 ms | 75.836 ms | — | 28.103 ms | 10.991 ms | 10.043 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | 16.377 s | 8.856 s | 5.559 s | 3.792 s | 6.976 s | 3.593 s | 1.967 s | 1.187 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.954 ms | 4.856 ms | 2.961 ms | 2.003 ms | 5.255 ms | 2.784 ms | 1.677 ms | 1.116 ms | 911.428 μs | 3.595 ms | 2.529 ms | 336.803 μs |
| interpolate! NUFFT | Float32 128^3 | 307.002 ms | 186.337 ms | 125.670 ms | 97.362 ms | 239.450 ms | 127.640 ms | 72.959 ms | 45.847 ms | 12.723 ms | 16.422 ms | 4.561 ms | 1.904 ms |
| interpolate! NUFFT | Float32 256^3 | 3.498 s | 1.980 s | 1.276 s | 917.061 ms | 2.992 s | 1.551 s | 866.222 ms | 529.164 ms | — | 72.243 ms | 25.789 ms | 17.658 ms |
| interpolate! NUFFT | Float32 512^3 | 31.922 s | 18.012 s | 11.453 s | 8.282 s | 24.896 s | 13.356 s | 7.715 s | 4.977 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 16.519 ms | 10.207 ms | 6.795 ms | 5.326 ms | 11.956 ms | 6.428 ms | 3.801 ms | 2.451 ms | 1.847 ms | 4.302 ms | 2.226 ms | 429.055 μs |
| interpolate! NUFFT | Float64 128^3 | 421.433 ms | 255.981 ms | 192.904 ms | 161.776 ms | 226.096 ms | 139.544 ms | 81.550 ms | 77.002 ms | 25.361 ms | 18.237 ms | 8.724 ms | 5.546 ms |
| interpolate! NUFFT | Float64 256^3 | 3.901 s | 2.356 s | 1.699 s | 1.365 s | 2.045 s | 1.258 s | 883.347 ms | 727.957 ms | — | 118.516 ms | 59.524 ms | 47.626 ms |
| interpolate! NUFFT | Float64 512^3 | 35.462 s | 20.845 s | 14.870 s | 13.148 s | 25.049 s | 14.272 s | 8.837 s | 9.494 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 21.974 ms | 14.169 ms | 10.812 ms | 9.007 ms | 17.750 ms | 9.778 ms | 5.963 ms | 4.100 ms | 3.417 ms | 6.116 ms | 3.187 ms | 946.980 μs |
| interpolate! trilinear | Float32 128^3 | 2.029 ms | 1.026 ms | 520.481 μs | 291.684 μs | 1.327 ms | 663.706 μs | 335.743 μs | 179.412 μs | 255.582 μs | 1.719 ms | 1.024 ms | 66.201 μs |
| interpolate! trilinear | Float32 256^3 | 54.025 ms | 28.417 ms | 15.244 ms | 8.952 ms | 14.416 ms | 7.774 ms | 3.689 ms | 1.844 ms | — | 3.594 ms | 1.399 ms | 253.583 μs |
| interpolate! trilinear | Float32 512^3 | 482.975 ms | 257.090 ms | 148.905 ms | 97.158 ms | 436.733 ms | 248.707 ms | 120.209 ms | 63.383 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 227.223 μs | 124.212 μs | 77.823 μs | 55.854 μs | 146.781 μs | 79.010 μs | 47.651 μs | 33.231 μs | 65.160 μs | 1.448 ms | 1.129 ms | 59.670 μs |
| interpolate! trilinear | Float64 128^3 | 2.207 ms | 1.220 ms | 654.707 μs | 379.324 μs | 1.348 ms | 691.856 μs | 351.624 μs | 188.992 μs | 325.503 μs | 1.772 ms | 1.114 ms | 84.371 μs |
| interpolate! trilinear | Float64 256^3 | 60.265 ms | 31.979 ms | 19.700 ms | 13.551 ms | 33.564 ms | 16.440 ms | 8.292 ms | 4.185 ms | — | 4.014 ms | 1.577 ms | 417.505 μs |
| interpolate! trilinear | Float64 512^3 | 511.520 ms | 279.357 ms | 155.258 ms | 105.064 ms | 451.533 ms | 227.685 ms | 129.156 ms | 65.104 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 239.320 μs | 132.276 μs | 81.600 μs | 57.898 μs | 162.421 μs | 86.470 μs | 50.161 μs | 33.570 μs | 65.930 μs | 1.530 ms | 1.074 ms | 62.471 μs |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.085 ms | 6.996 ms | 8.357 ms | 7.972 ms | 6.958 ms | 4.938 ms | 6.016 ms | 6.042 ms | 2.099 ms | 27.761 ms | 1.411 ms | 320.423 μs |
| co-spectrum vec.vec | Float32 256^3 | 64.252 ms | 47.546 ms | 45.730 ms | 42.525 ms | 55.721 ms | 36.952 ms | 33.381 ms | 29.625 ms | — | 97.666 ms | 3.247 ms | 957.282 μs |
| co-spectrum vec.vec | Float32 512^3 | 510.689 ms | 356.734 ms | 266.038 ms | 229.071 ms | 440.861 ms | 271.900 ms | 192.738 ms | 152.078 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.044 ms | 1.386 ms | 1.531 ms | 1.605 ms | 905.370 μs | 937.409 μs | 1.263 ms | 1.340 ms | 491.824 μs | 17.761 ms | 1.358 ms | 178.142 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.408 ms | 6.415 ms | 5.999 ms | 5.322 ms | 7.259 ms | 5.192 ms | 4.525 ms | 4.756 ms | 2.194 ms | 29.708 ms | 28.038 ms | 400.374 μs |
| co-spectrum vec.vec | Float64 256^3 | 67.386 ms | 48.673 ms | 36.466 ms | 31.465 ms | 58.750 ms | 38.055 ms | 27.222 ms | 23.641 ms | — | 109.563 ms | 66.499 ms | 1.283 ms |
| co-spectrum vec.vec | Float64 512^3 | 556.430 ms | 370.769 ms | 239.490 ms | 195.985 ms | 477.002 ms | 293.798 ms | 177.172 ms | 132.471 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.062 ms | 792.529 μs | 975.719 μs | 996.385 μs | 946.920 μs | 782.498 μs | 856.229 μs | 964.611 μs | 482.135 μs | 16.075 ms | 15.998 ms | 189.722 μs |
| cov vector | Float32 128^3 | 2.186 ms | 1.196 ms | 635.824 μs | 349.018 μs | 1.130 ms | 578.715 μs | 309.064 μs | 177.902 μs | — | — | 2.138 ms | 237.962 μs |
| cov vector | Float32 256^3 | 20.981 ms | 13.773 ms | 11.064 ms | 10.073 ms | 12.210 ms | 8.008 ms | 5.154 ms | 4.641 ms | — | — | 7.277 ms | 949.682 μs |
| cov vector | Float32 512^3 | 170.198 ms | 115.954 ms | 94.519 ms | 88.892 ms | 93.027 ms | 64.637 ms | 55.246 ms | 55.327 ms | — | — | — | — |
| cov vector | Float32 64^3 | 252.111 μs | 140.531 μs | 78.922 μs | 61.631 μs | 144.571 μs | 80.271 μs | 45.690 μs | 37.131 μs | — | — | 1.422 ms | 181.702 μs |
| cov vector | Float64 128^3 | 3.974 ms | 2.651 ms | 2.119 ms | 1.722 ms | 2.218 ms | 1.121 ms | 572.076 μs | 328.614 μs | — | — | 2.732 ms | 367.174 μs |
| cov vector | Float64 256^3 | 34.336 ms | 26.329 ms | 22.854 ms | 21.660 ms | 25.108 ms | 15.006 ms | 12.475 ms | 12.556 ms | — | — | 11.516 ms | 1.520 ms |
| cov vector | Float64 512^3 | 274.468 ms | 212.966 ms | 190.661 ms | 179.491 ms | 186.783 ms | 129.433 ms | 111.115 ms | 111.476 ms | — | — | — | — |
| cov vector | Float64 64^3 | 352.395 μs | 191.454 μs | 106.185 μs | 75.328 μs | 272.233 μs | 145.701 μs | 80.661 μs | 54.691 μs | — | — | 1.558 ms | 197.582 μs |
| cross-correlation vec.vec | Float32 128^3 | 37.668 ms | 33.117 ms | 33.833 ms | 33.859 ms | 33.089 ms | 24.582 ms | 21.935 ms | 21.250 ms | 5.891 ms | 43.640 ms | 2.623 ms | 689.017 μs |
| cross-correlation vec.vec | Float32 256^3 | 410.005 ms | 309.678 ms | 266.738 ms | 252.627 ms | 401.562 ms | 274.237 ms | 203.810 ms | 176.983 ms | — | 186.915 ms | 10.779 ms | 5.839 ms |
| cross-correlation vec.vec | Float32 512^3 | 3.812 s | 2.621 s | 1.856 s | 1.636 s | 2.919 s | 2.052 s | 1.380 s | 1.186 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.645 ms | 5.312 ms | 5.499 ms | 5.723 ms | 3.875 ms | 3.581 ms | 3.781 ms | 3.704 ms | 1.025 ms | 20.682 ms | 1.487 ms | 273.133 μs |
| cross-correlation vec.vec | Float64 128^3 | 57.857 ms | 55.261 ms | 41.756 ms | 49.781 ms | 47.098 ms | 37.457 ms | 33.804 ms | 31.617 ms | 9.144 ms | 52.055 ms | 45.505 ms | 2.096 ms |
| cross-correlation vec.vec | Float64 256^3 | 581.596 ms | 456.868 ms | 371.550 ms | 351.100 ms | 576.033 ms | 392.788 ms | 295.324 ms | 222.234 ms | — | 217.471 ms | 136.407 ms | 15.013 ms |
| cross-correlation vec.vec | Float64 512^3 | 5.734 s | 3.790 s | 2.943 s | 2.533 s | 4.618 s | 2.971 s | 2.109 s | 1.793 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.685 ms | 5.331 ms | 5.601 ms | 5.462 ms | 4.213 ms | 3.555 ms | 3.455 ms | 3.310 ms | 1.557 ms | 20.881 ms | 23.938 ms | 323.123 μs |
| inner spectral | Float32 128^3 | 2.464 ms | 1.649 ms | 1.380 ms | 1.229 ms | 1.427 ms | 809.278 μs | 506.145 μs | 363.494 μs | 669.926 μs | 2.049 ms | 1.208 ms | 237.512 μs |
| inner spectral | Float32 256^3 | 21.204 ms | 16.705 ms | 14.751 ms | 13.651 ms | 12.813 ms | 7.724 ms | 7.099 ms | 7.136 ms | — | 3.999 ms | 1.667 ms | 744.770 μs |
| inner spectral | Float32 512^3 | 164.737 ms | 128.807 ms | 112.670 ms | 106.006 ms | 104.735 ms | 77.564 ms | 70.268 ms | 70.246 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 305.237 μs | 196.626 μs | 138.790 μs | 113.332 μs | 206.762 μs | 122.022 μs | 81.951 μs | 74.161 μs | 275.972 μs | 1.780 ms | 1.137 ms | 207.142 μs |
| inner spectral | Float64 128^3 | 4.140 ms | 3.536 ms | 3.107 ms | 2.850 ms | 1.863 ms | 1.094 ms | 732.648 μs | 620.996 μs | 811.337 μs | 2.410 ms | 1.351 ms | 344.324 μs |
| inner spectral | Float64 256^3 | 34.526 ms | 29.659 ms | 27.514 ms | 26.111 ms | 18.333 ms | 15.961 ms | 15.949 ms | 14.944 ms | — | 7.953 ms | 2.871 ms | 1.236 ms |
| inner spectral | Float64 512^3 | 255.858 ms | 226.744 ms | 211.250 ms | 199.676 ms | 127.745 ms | 125.457 ms | 124.319 ms | 125.474 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 309.165 μs | 210.033 μs | 148.238 μs | 127.392 μs | 222.282 μs | 137.651 μs | 88.260 μs | 78.030 μs | 293.003 μs | 1.765 ms | 1.142 ms | 196.812 μs |
| inner vec.vec | Float32 128^3 | 1.323 ms | 950.160 μs | 816.944 μs | 711.423 μs | 377.544 μs | 193.112 μs | 101.822 μs | 73.491 μs | 308.353 μs | 1.623 ms | 799.729 μs | 115.851 μs |
| inner vec.vec | Float32 256^3 | 13.030 ms | 12.119 ms | 11.438 ms | 10.654 ms | 6.829 ms | 6.018 ms | 5.755 ms | 5.897 ms | — | 3.382 ms | 1.316 ms | 572.848 μs |
| inner vec.vec | Float32 512^3 | 104.969 ms | 99.526 ms | 96.158 ms | 89.634 ms | 61.151 ms | 56.569 ms | 55.403 ms | 55.867 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 69.599 μs | 38.926 μs | 20.420 μs | 14.923 μs | 45.930 μs | 25.940 μs | 14.820 μs | 10.090 μs | 98.731 μs | 1.278 ms | 780.817 μs | 89.681 μs |
| inner vec.vec | Float64 128^3 | 2.926 ms | 2.506 ms | 2.293 ms | 2.133 ms | 1.117 ms | 575.026 μs | 360.634 μs | 263.053 μs | 552.615 μs | 1.860 ms | 982.752 μs | 254.533 μs |
| inner vec.vec | Float64 256^3 | 25.489 ms | 24.512 ms | 23.201 ms | 22.283 ms | 15.858 ms | 14.227 ms | 13.217 ms | 13.329 ms | — | 5.634 ms | 2.062 ms | 1.070 ms |
| inner vec.vec | Float64 512^3 | 212.011 ms | 198.041 ms | 189.067 ms | 178.007 ms | 125.374 ms | 112.648 ms | 111.518 ms | 112.181 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 136.661 μs | 76.001 μs | 39.834 μs | 25.515 μs | 87.211 μs | 46.770 μs | 26.170 μs | 17.970 μs | 162.792 μs | 1.434 ms | 245.052 μs | 100.981 μs |
| integral scalar | Float32 128^3 | 113.205 μs | 61.734 μs | 29.627 μs | 19.984 μs | 61.830 μs | 38.640 μs | 20.230 μs | 12.961 μs | 228.932 μs | 1.318 ms | 1.145 ms | 91.911 μs |
| integral scalar | Float32 256^3 | 2.043 ms | 1.488 ms | 1.294 ms | 1.174 ms | 585.106 μs | 302.284 μs | 159.302 μs | 94.991 μs | — | 9.002 ms | 2.255 ms | 251.814 μs |
| integral scalar | Float32 512^3 | 19.678 ms | 15.746 ms | 14.784 ms | 14.224 ms | 11.765 ms | 9.151 ms | 8.872 ms | 9.104 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 9.752 μs | 6.550 μs | 5.648 μs | 5.799 μs | 6.860 μs | 4.810 μs | 4.269 μs | 5.200 μs | 95.301 μs | 1.534 ms | 893.778 μs | 85.131 μs |
| integral scalar | Float64 128^3 | 253.999 μs | 119.139 μs | 66.851 μs | 38.885 μs | 123.651 μs | 62.481 μs | 36.421 μs | 23.830 μs | 221.812 μs | 2.553 ms | 1.176 ms | 106.181 μs |
| integral scalar | Float64 256^3 | 4.362 ms | 3.558 ms | 3.275 ms | 3.026 ms | 2.002 ms | 1.024 ms | 866.869 μs | 944.660 μs | — | 10.817 ms | 2.627 ms | 268.463 μs |
| integral scalar | Float64 512^3 | 37.576 ms | 32.135 ms | 30.033 ms | 29.174 ms | 20.747 ms | 18.825 ms | 17.860 ms | 18.059 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.255 μs | 12.381 μs | 8.008 μs | 7.622 μs | 15.791 μs | 7.481 μs | 5.935 μs | 5.583 μs | 95.391 μs | 1.583 ms | 898.700 μs | 78.711 μs |
| integral spectral vec | Float32 128^3 | 66.121 ns | 66.808 ns | 67.436 ns | 82.462 ns | 68.238 ns | 70.052 ns | 68.402 ns | 68.248 ns | — | — | 834.448 μs | 50.071 μs |
| integral spectral vec | Float32 256^3 | 66.484 ns | 67.441 ns | 67.777 ns | 83.150 ns | 68.956 ns | 70.666 ns | 69.263 ns | 68.401 ns | — | — | 751.115 μs | 47.821 μs |
| integral spectral vec | Float32 512^3 | 66.418 ns | 67.951 ns | 67.861 ns | 84.149 ns | 69.079 ns | 73.300 ns | 72.506 ns | 69.048 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 65.864 ns | 66.969 ns | 66.995 ns | 81.421 ns | 68.261 ns | 69.591 ns | 67.930 ns | 68.167 ns | — | — | 827.616 μs | 57.460 μs |
| integral spectral vec | Float64 128^3 | 69.031 ns | 68.348 ns | 69.255 ns | 69.653 ns | 71.460 ns | 75.201 ns | 75.208 ns | 76.098 ns | — | — | 822.851 μs | 53.450 μs |
| integral spectral vec | Float64 256^3 | 69.175 ns | 68.795 ns | 69.299 ns | 69.459 ns | 72.191 ns | 78.151 ns | 76.447 ns | 76.541 ns | — | — | 756.905 μs | 47.990 μs |
| integral spectral vec | Float64 512^3 | 69.652 ns | 69.119 ns | 70.031 ns | 70.912 ns | 74.430 ns | 80.617 ns | 80.837 ns | 81.290 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 68.569 ns | 67.415 ns | 67.973 ns | 68.004 ns | 75.332 ns | 77.091 ns | 74.401 ns | 77.265 ns | — | — | 830.452 μs | 46.500 μs |
| l2norm vec | Float32 128^3 | 527.126 μs | 314.725 μs | 177.046 μs | 94.345 μs | 240.453 μs | 129.021 μs | 67.541 μs | 39.771 μs | 196.632 μs | 1.582 ms | 822.739 μs | 99.141 μs |
| l2norm vec | Float32 256^3 | 7.466 ms | 5.850 ms | 5.401 ms | 4.965 ms | 4.061 ms | 2.854 ms | 1.979 ms | 1.994 ms | — | 3.219 ms | 1.170 ms | 337.534 μs |
| l2norm vec | Float32 512^3 | 62.425 ms | 49.766 ms | 46.270 ms | 44.568 ms | 39.855 ms | 30.163 ms | 26.835 ms | 27.028 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 49.336 μs | 27.655 μs | 18.780 μs | 12.689 μs | 32.651 μs | 17.400 μs | 9.700 μs | 7.230 μs | 85.641 μs | 1.361 ms | 752.910 μs | 90.451 μs |
| l2norm vec | Float64 128^3 | 1.520 ms | 1.074 ms | 797.428 μs | 711.305 μs | 559.425 μs | 236.442 μs | 127.902 μs | 83.371 μs | 344.333 μs | 1.876 ms | 947.089 μs | 149.041 μs |
| l2norm vec | Float64 256^3 | 14.901 ms | 12.033 ms | 11.085 ms | 10.333 ms | 12.023 ms | 6.503 ms | 5.658 ms | 5.589 ms | — | 5.670 ms | 2.055 ms | 607.376 μs |
| l2norm vec | Float64 512^3 | 120.359 ms | 99.080 ms | 91.019 ms | 87.536 ms | 85.581 ms | 62.266 ms | 54.677 ms | 54.762 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 92.392 μs | 50.919 μs | 33.041 μs | 18.714 μs | 55.050 μs | 29.200 μs | 16.920 μs | 11.031 μs | 134.871 μs | 1.402 ms | 775.243 μs | 106.782 μs |
| lpnorm vec Inf | Float32 128^3 | 1.334 ms | 1.254 ms | 1.087 ms | 947.451 μs | 460.094 μs | 386.324 μs | 342.394 μs | 320.343 μs | 592.145 μs | 3.080 ms | 1.228 ms | 132.462 μs |
| lpnorm vec Inf | Float32 256^3 | 13.946 ms | 13.173 ms | 11.556 ms | 10.649 ms | 7.892 ms | 7.677 ms | 7.971 ms | 7.951 ms | — | 13.216 ms | 3.216 ms | 588.647 μs |
| lpnorm vec Inf | Float32 512^3 | 114.652 ms | 113.167 ms | 93.098 ms | 85.454 ms | 78.662 ms | 91.817 ms | 75.786 ms | 70.509 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 96.370 μs | 94.096 μs | 73.549 μs | 84.637 μs | 62.201 μs | 49.281 μs | 41.430 μs | 42.801 μs | 155.751 μs | 1.641 ms | 952.744 μs | 117.821 μs |
| lpnorm vec Inf | Float64 128^3 | 3.053 ms | 3.183 ms | 2.631 ms | 2.427 ms | 1.176 ms | 1.104 ms | 950.840 μs | 1.004 ms | 660.476 μs | 3.883 ms | 1.737 ms | 249.663 μs |
| lpnorm vec Inf | Float64 256^3 | 27.785 ms | 26.396 ms | 22.963 ms | 21.540 ms | 16.833 ms | 15.997 ms | 16.084 ms | 15.901 ms | — | 14.730 ms | 5.455 ms | 976.950 μs |
| lpnorm vec Inf | Float64 512^3 | 223.561 ms | 213.045 ms | 187.236 ms | 172.938 ms | 148.753 ms | 167.285 ms | 141.274 ms | 139.258 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 233.247 μs | 174.915 μs | 147.324 μs | 136.472 μs | 111.682 μs | 93.541 μs | 76.770 μs | 72.551 μs | 166.092 μs | 1.711 ms | 1.019 ms | 117.481 μs |
| maximum scalar | Float32 128^3 | 338.342 μs | 176.640 μs | 92.078 μs | 77.879 μs | 237.443 μs | 120.201 μs | 60.991 μs | 33.130 μs | 223.322 μs | 2.331 ms | 1.138 ms | 93.121 μs |
| maximum scalar | Float32 256^3 | 3.407 ms | 1.898 ms | 1.402 ms | 1.188 ms | 2.005 ms | 967.221 μs | 482.975 μs | 247.103 μs | — | 9.121 ms | 2.329 ms | 246.133 μs |
| maximum scalar | Float32 512^3 | 24.096 ms | 17.667 ms | 15.267 ms | 14.287 ms | 31.718 ms | 14.344 ms | 9.074 ms | 8.171 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 42.020 μs | 24.577 μs | 13.945 μs | 11.582 μs | 29.401 μs | 15.830 μs | 9.330 μs | 6.600 μs | 101.731 μs | 1.564 ms | 893.442 μs | 88.571 μs |
| maximum scalar | Float64 128^3 | 565.846 μs | 278.395 μs | 143.150 μs | 133.460 μs | 447.755 μs | 221.782 μs | 113.391 μs | 59.420 μs | 244.072 μs | 2.772 ms | 1.325 ms | 117.222 μs |
| maximum scalar | Float64 256^3 | 6.135 ms | 3.934 ms | 3.395 ms | 3.044 ms | 3.973 ms | 2.010 ms | 1.106 ms | 801.808 μs | — | 12.659 ms | 3.212 ms | 292.243 μs |
| maximum scalar | Float64 512^3 | 48.714 ms | 33.445 ms | 30.564 ms | 29.127 ms | 44.626 ms | 27.121 ms | 18.977 ms | 17.462 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 65.250 μs | 36.625 μs | 21.048 μs | 14.741 μs | 55.500 μs | 28.481 μs | 16.030 μs | 10.100 μs | 99.451 μs | 1.634 ms | 932.224 μs | 85.131 μs |
| maximum(norm) vec | Float32 128^3 | 1.799 ms | 947.000 μs | 474.822 μs | 245.647 μs | 772.477 μs | 390.744 μs | 201.212 μs | 103.712 μs | — | — | 1.235 ms | 115.941 μs |
| maximum(norm) vec | Float32 256^3 | 15.151 ms | 8.169 ms | 5.709 ms | 5.004 ms | 7.503 ms | 3.522 ms | 2.099 ms | 2.089 ms | — | — | 2.845 ms | 365.655 μs |
| maximum(norm) vec | Float32 512^3 | 118.979 ms | 67.746 ms | 49.904 ms | 45.549 ms | 58.291 ms | 38.899 ms | 29.278 ms | 28.047 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 220.737 μs | 116.548 μs | 61.320 μs | 74.226 μs | 97.071 μs | 50.370 μs | 26.420 μs | 15.460 μs | — | — | 914.535 μs | 93.321 μs |
| maximum(norm) vec | Float64 128^3 | 5.214 ms | 2.699 ms | 1.383 ms | 823.695 μs | 1.580 ms | 795.558 μs | 400.774 μs | 204.562 μs | — | — | 1.426 ms | 216.182 μs |
| maximum(norm) vec | Float64 256^3 | 42.183 ms | 21.531 ms | 12.660 ms | 11.079 ms | 14.147 ms | 8.368 ms | 6.080 ms | 5.860 ms | — | — | 4.920 ms | 1.051 ms |
| maximum(norm) vec | Float64 512^3 | 336.030 ms | 171.441 ms | 106.202 ms | 92.733 ms | 126.692 ms | 73.096 ms | 57.719 ms | 56.885 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 638.858 μs | 329.832 μs | 168.017 μs | 90.193 μs | 196.732 μs | 101.611 μs | 52.360 μs | 28.390 μs | — | — | 976.255 μs | 100.421 μs |
| mean spectral vec | Float32 128^3 | 68.912 ns | 70.049 ns | 70.289 ns | 70.490 ns | 70.616 ns | 74.179 ns | 72.447 ns | 71.531 ns | — | — | 775.503 μs | 51.471 μs |
| mean spectral vec | Float32 256^3 | 69.607 ns | 70.568 ns | 70.640 ns | 70.658 ns | 71.119 ns | 75.293 ns | 73.717 ns | 71.900 ns | — | — | 817.100 μs | 49.990 μs |
| mean spectral vec | Float32 512^3 | 70.361 ns | 74.360 ns | 70.561 ns | 72.088 ns | 71.848 ns | 77.568 ns | 75.952 ns | 75.668 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 69.389 ns | 70.450 ns | 69.490 ns | 69.618 ns | 70.258 ns | 73.769 ns | 72.496 ns | 71.295 ns | — | — | 833.490 μs | 50.120 μs |
| mean spectral vec | Float64 128^3 | 71.489 ns | 72.792 ns | 72.690 ns | 72.359 ns | 76.210 ns | 79.104 ns | 78.333 ns | 80.456 ns | — | — | 837.727 μs | 58.231 μs |
| mean spectral vec | Float64 256^3 | 72.023 ns | 72.870 ns | 72.888 ns | 73.692 ns | 78.897 ns | 81.434 ns | 79.011 ns | 81.477 ns | — | — | 783.083 μs | 47.140 μs |
| mean spectral vec | Float64 512^3 | 72.260 ns | 79.126 ns | 73.249 ns | 74.082 ns | 80.031 ns | 83.966 ns | 83.134 ns | 86.210 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 71.541 ns | 71.722 ns | 71.249 ns | 70.881 ns | 80.508 ns | 80.745 ns | 77.880 ns | 81.841 ns | — | — | 824.640 μs | 47.770 μs |
| mean vector | Float32 128^3 | 436.861 μs | 275.585 μs | 172.486 μs | 97.294 μs | 194.042 μs | 107.401 μs | 63.710 μs | 44.761 μs | 633.756 μs | 4.808 ms | 1.901 ms | 172.472 μs |
| mean vector | Float32 256^3 | 6.719 ms | 5.740 ms | 5.323 ms | 5.010 ms | 3.465 ms | 2.670 ms | 2.396 ms | 2.415 ms | — | 16.657 ms | 5.493 ms | 637.218 μs |
| mean vector | Float32 512^3 | 58.139 ms | 48.680 ms | 44.902 ms | 43.607 ms | 31.587 ms | 27.203 ms | 26.862 ms | 27.171 ms | — | — | — | — |
| mean vector | Float32 64^3 | 41.575 μs | 28.263 μs | 19.642 μs | 22.649 μs | 24.960 μs | 17.480 μs | 12.950 μs | 15.591 μs | 162.362 μs | 1.846 ms | 1.218 ms | 163.812 μs |
| mean vector | Float64 128^3 | 1.368 ms | 933.480 μs | 770.661 μs | 717.190 μs | 400.084 μs | 206.192 μs | 121.701 μs | 82.151 μs | 657.486 μs | 5.195 ms | 1.828 ms | 200.792 μs |
| mean vector | Float64 256^3 | 14.052 ms | 11.870 ms | 11.077 ms | 10.448 ms | 8.677 ms | 6.527 ms | 6.571 ms | 6.650 ms | — | 17.799 ms | 6.406 ms | 677.607 μs |
| mean vector | Float64 512^3 | 113.193 ms | 97.006 ms | 90.840 ms | 87.788 ms | 59.314 ms | 56.142 ms | 54.490 ms | 54.876 ms | — | — | — | — |
| mean vector | Float64 64^3 | 84.427 μs | 48.544 μs | 30.783 μs | 29.104 μs | 45.720 μs | 31.090 μs | 20.011 μs | 18.930 μs | 156.311 μs | 1.913 ms | 1.240 ms | 143.312 μs |
| mean(det) tensor | Float32 128^3 | 2.417 ms | 1.854 ms | 1.598 ms | 1.497 ms | 773.138 μs | 381.133 μs | 196.882 μs | 120.681 μs | — | — | 1.308 ms | 226.472 μs |
| mean(det) tensor | Float32 256^3 | 21.277 ms | 20.099 ms | 18.172 ms | 17.264 ms | 15.340 ms | 11.632 ms | 10.382 ms | 10.387 ms | — | — | 3.279 ms | 835.851 μs |
| mean(det) tensor | Float32 512^3 | 172.153 ms | 163.945 ms | 149.988 ms | 143.179 ms | 107.381 ms | 89.687 ms | 84.190 ms | 85.147 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 104.177 μs | 54.345 μs | 28.867 μs | 21.326 μs | 67.100 μs | 36.870 μs | 23.440 μs | 14.580 μs | — | — | 917.622 μs | 99.801 μs |
| mean(det) tensor | Float64 128^3 | 5.149 ms | 4.545 ms | 3.887 ms | 3.631 ms | 2.576 ms | 1.547 ms | 1.200 ms | 1.211 ms | — | — | 1.473 ms | 293.243 μs |
| mean(det) tensor | Float64 256^3 | 41.379 ms | 40.368 ms | 37.887 ms | 35.177 ms | 30.727 ms | 23.328 ms | 21.606 ms | 21.519 ms | — | — | 4.648 ms | 1.535 ms |
| mean(det) tensor | Float64 512^3 | 325.205 ms | 326.577 ms | 300.634 ms | 283.598 ms | 197.593 ms | 180.352 ms | 168.578 ms | 169.265 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 224.659 μs | 127.893 μs | 74.006 μs | 38.604 μs | 134.761 μs | 67.741 μs | 44.781 μs | 28.990 μs | — | — | 946.084 μs | 97.821 μs |
| mean(norm) vec | Float32 128^3 | 1.550 ms | 812.954 μs | 406.340 μs | 213.901 μs | 607.256 μs | 302.083 μs | 159.612 μs | 82.771 μs | — | — | 1.196 ms | 108.001 μs |
| mean(norm) vec | Float32 256^3 | 12.965 ms | 7.522 ms | 5.637 ms | 4.998 ms | 6.276 ms | 3.626 ms | 2.072 ms | 2.088 ms | — | — | 2.802 ms | 360.335 μs |
| mean(norm) vec | Float32 512^3 | 101.664 ms | 63.563 ms | 49.462 ms | 45.365 ms | 51.540 ms | 37.026 ms | 29.491 ms | 28.177 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 189.160 μs | 100.213 μs | 52.956 μs | 67.516 μs | 76.500 μs | 39.891 μs | 21.240 μs | 15.961 μs | — | — | 914.351 μs | 97.771 μs |
| mean(norm) vec | Float64 128^3 | 5.147 ms | 2.663 ms | 1.349 ms | 830.769 μs | 1.429 ms | 723.817 μs | 364.374 μs | 190.242 μs | — | — | 1.407 ms | 229.192 μs |
| mean(norm) vec | Float64 256^3 | 41.522 ms | 21.232 ms | 12.635 ms | 11.159 ms | 13.150 ms | 8.153 ms | 6.190 ms | 5.822 ms | — | — | 4.267 ms | 947.129 μs |
| mean(norm) vec | Float64 512^3 | 331.193 ms | 168.941 ms | 105.211 ms | 92.581 ms | 116.479 ms | 71.465 ms | 57.533 ms | 56.762 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 631.535 μs | 326.034 μs | 168.591 μs | 88.614 μs | 180.422 μs | 92.741 μs | 47.760 μs | 26.530 μs | — | — | 971.194 μs | 95.531 μs |
| mean(tr) tensor | Float32 128^3 | 399.009 μs | 245.872 μs | 147.045 μs | 59.212 μs | 197.612 μs | 98.101 μs | 57.650 μs | 36.040 μs | — | — | 1.161 ms | 106.571 μs |
| mean(tr) tensor | Float32 256^3 | 6.131 ms | 5.862 ms | 5.338 ms | 4.961 ms | 3.098 ms | 2.414 ms | 2.137 ms | 2.248 ms | — | — | 2.794 ms | 358.075 μs |
| mean(tr) tensor | Float32 512^3 | 51.993 ms | 49.935 ms | 47.562 ms | 45.092 ms | 33.708 ms | 28.992 ms | 27.638 ms | 28.163 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 35.048 μs | 18.580 μs | 11.830 μs | 10.177 μs | 25.290 μs | 12.160 μs | 7.840 μs | 6.610 μs | — | — | 867.232 μs | 93.221 μs |
| mean(tr) tensor | Float64 128^3 | 1.280 ms | 949.800 μs | 800.417 μs | 692.895 μs | 407.964 μs | 181.662 μs | 100.601 μs | 72.231 μs | — | — | 1.198 ms | 147.592 μs |
| mean(tr) tensor | Float64 256^3 | 12.499 ms | 11.853 ms | 11.372 ms | 10.742 ms | 7.152 ms | 6.566 ms | 6.289 ms | 6.262 ms | — | — | 3.101 ms | 594.726 μs |
| mean(tr) tensor | Float64 512^3 | 104.298 ms | 100.708 ms | 95.066 ms | 88.987 ms | 65.938 ms | 60.227 ms | 55.773 ms | 56.596 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 66.817 μs | 37.152 μs | 19.666 μs | 15.579 μs | 43.300 μs | 24.240 μs | 14.460 μs | 10.011 μs | — | — | 871.936 μs | 90.111 μs |
| radial_correlation vec | Float32 128^3 | 35.571 ms | 31.061 ms | 32.612 ms | 33.624 ms | 30.705 ms | 22.879 ms | 21.468 ms | 20.363 ms | 5.783 ms | 42.875 ms | 2.463 ms | 665.806 μs |
| radial_correlation vec | Float32 256^3 | 395.970 ms | 314.312 ms | 262.237 ms | 252.597 ms | 385.168 ms | 264.612 ms | 195.467 ms | 171.916 ms | — | 185.439 ms | 10.272 ms | 5.622 ms |
| radial_correlation vec | Float32 512^3 | 3.675 s | 2.544 s | 1.847 s | 1.613 s | 2.757 s | 1.934 s | 1.351 s | 1.145 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.240 ms | 5.099 ms | 5.427 ms | 5.669 ms | 3.548 ms | 3.250 ms | 3.561 ms | 3.605 ms | 1.010 ms | 19.917 ms | 1.567 ms | 273.392 μs |
| radial_correlation vec | Float64 128^3 | 56.335 ms | 54.616 ms | 40.099 ms | 53.887 ms | 44.763 ms | 36.098 ms | 32.339 ms | 30.125 ms | 9.025 ms | 52.060 ms | 46.125 ms | 2.031 ms |
| radial_correlation vec | Float64 256^3 | 566.203 ms | 448.656 ms | 331.754 ms | 311.984 ms | 558.148 ms | 349.435 ms | 282.187 ms | 247.207 ms | — | 219.151 ms | 135.923 ms | 14.544 ms |
| radial_correlation vec | Float64 512^3 | 5.581 s | 3.664 s | 2.900 s | 2.448 s | 4.401 s | 2.851 s | 2.011 s | 1.735 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.404 ms | 5.254 ms | 5.408 ms | 5.205 ms | 3.810 ms | 3.281 ms | 3.342 ms | 3.208 ms | 1.413 ms | 21.203 ms | 24.320 ms | 311.313 μs |
| radial_spectrum vec | Float32 128^3 | 7.479 ms | 6.857 ms | 8.635 ms | 8.641 ms | 6.328 ms | 4.708 ms | 5.774 ms | 6.035 ms | 1.415 ms | 27.166 ms | 1.719 ms | 280.093 μs |
| radial_spectrum vec | Float32 256^3 | 59.601 ms | 42.973 ms | 45.793 ms | 44.093 ms | 50.100 ms | 32.849 ms | 31.389 ms | 30.048 ms | — | 96.772 ms | 3.256 ms | 940.122 μs |
| radial_spectrum vec | Float32 512^3 | 474.263 ms | 342.922 ms | 255.081 ms | 223.928 ms | 399.890 ms | 237.744 ms | 180.877 ms | 152.155 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 983.294 μs | 1.382 ms | 1.620 ms | 1.671 ms | 822.799 μs | 934.549 μs | 1.164 ms | 1.323 ms | 344.443 μs | 16.995 ms | 1.153 ms | 191.372 μs |
| radial_spectrum vec | Float64 128^3 | 7.569 ms | 5.352 ms | 6.003 ms | 6.026 ms | 6.548 ms | 4.606 ms | 4.452 ms | 4.572 ms | 1.515 ms | 29.791 ms | 27.830 ms | 421.274 μs |
| radial_spectrum vec | Float64 256^3 | 60.230 ms | 44.482 ms | 35.347 ms | 30.127 ms | 51.941 ms | 32.003 ms | 25.006 ms | 24.194 ms | — | 110.504 ms | 67.622 ms | 1.420 ms |
| radial_spectrum vec | Float64 512^3 | 483.046 ms | 338.977 ms | 217.670 ms | 173.729 ms | 414.296 ms | 251.291 ms | 163.540 ms | 126.319 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 973.498 μs | 917.307 μs | 1.154 ms | 1.081 ms | 848.879 μs | 683.176 μs | 836.318 μs | 939.811 μs | 380.613 μs | 16.740 ms | 15.812 ms | 192.401 μs |
| var scalar | Float32 128^3 | 234.246 μs | 129.282 μs | 70.053 μs | 44.985 μs | 132.961 μs | 78.660 μs | 42.360 μs | 28.331 μs | — | — | 1.572 ms | 138.472 μs |
| var scalar | Float32 256^3 | 4.152 ms | 3.120 ms | 2.626 ms | 2.433 ms | 1.274 ms | 647.997 μs | 336.603 μs | 198.012 μs | — | — | 3.915 ms | 435.685 μs |
| var scalar | Float32 512^3 | 39.003 ms | 31.677 ms | 29.871 ms | 28.628 ms | 29.830 ms | 19.872 ms | 17.961 ms | 18.160 ms | — | — | — | — |
| var scalar | Float32 64^3 | 24.247 μs | 16.574 μs | 11.813 μs | 14.166 μs | 14.620 μs | 8.940 μs | 7.561 μs | 8.970 μs | — | — | 1.096 ms | 123.921 μs |
| var scalar | Float64 128^3 | 546.656 μs | 248.252 μs | 136.036 μs | 84.573 μs | 253.612 μs | 127.801 μs | 73.641 μs | 50.001 μs | — | — | 1.572 ms | 155.162 μs |
| var scalar | Float64 256^3 | 8.784 ms | 7.375 ms | 6.561 ms | 6.126 ms | 4.187 ms | 2.206 ms | 1.771 ms | 1.833 ms | — | — | 4.570 ms | 492.935 μs |
| var scalar | Float64 512^3 | 74.897 ms | 64.156 ms | 60.257 ms | 58.039 ms | 42.689 ms | 39.502 ms | 36.150 ms | 36.107 ms | — | — | — | — |
| var scalar | Float64 64^3 | 53.158 μs | 26.763 μs | 17.054 μs | 16.591 μs | 32.290 μs | 17.540 μs | 11.161 μs | 11.540 μs | — | — | 1.098 ms | 122.062 μs |
| var spectral scalar | Float32 128^3 | 131.168 μs | 90.581 μs | 63.026 μs | 55.036 μs | 93.971 μs | 60.791 μs | 42.991 μs | 44.670 μs | — | — | 1.240 ms | 164.291 μs |
| var spectral scalar | Float32 256^3 | 2.159 ms | 1.790 ms | 1.552 ms | 1.474 ms | 776.578 μs | 464.185 μs | 298.323 μs | 242.862 μs | — | — | 1.825 ms | 285.604 μs |
| var spectral scalar | Float32 512^3 | 19.896 ms | 17.643 ms | 16.883 ms | 16.393 ms | 13.016 ms | 10.353 ms | 10.886 ms | 10.904 ms | — | — | — | — |
| var spectral scalar | Float32 64^3 | 16.419 μs | 12.591 μs | 10.007 μs | 12.277 μs | 11.390 μs | 8.260 μs | 7.280 μs | 9.510 μs | — | — | 1.195 ms | 174.452 μs |
| var spectral scalar | Float64 128^3 | 267.726 μs | 183.123 μs | 110.537 μs | 84.526 μs | 145.461 μs | 88.161 μs | 62.510 μs | 61.791 μs | — | — | 1.354 ms | 175.142 μs |
| var spectral scalar | Float64 256^3 | 4.616 ms | 3.930 ms | 3.673 ms | 3.451 ms | 1.920 ms | 1.407 ms | 1.062 ms | 1.064 ms | — | — | 2.409 ms | 344.444 μs |
| var spectral scalar | Float64 512^3 | 39.258 ms | 34.734 ms | 33.293 ms | 31.746 ms | 20.979 ms | 20.574 ms | 20.223 ms | 20.484 ms | — | — | — | — |
| var spectral scalar | Float64 64^3 | 30.313 μs | 21.561 μs | 14.706 μs | 14.849 μs | 20.050 μs | 12.771 μs | 9.590 μs | 9.820 μs | — | — | 1.181 ms | 166.312 μs |
| weighted_inner vec | Float32 128^3 | 12.300 ms | 12.395 ms | 12.375 ms | 12.296 ms | 10.331 ms | 10.361 ms | 10.329 ms | 10.399 ms | — | — | 1.455 ms | 139.152 μs |
| weighted_inner vec | Float32 256^3 | 96.624 ms | 97.458 ms | 97.449 ms | 96.646 ms | 81.280 ms | 81.461 ms | 81.071 ms | 81.487 ms | — | — | 4.323 ms | 638.068 μs |
| weighted_inner vec | Float32 512^3 | 766.351 ms | 773.793 ms | 772.446 ms | 766.855 ms | 644.959 ms | 646.977 ms | 646.111 ms | 646.434 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.590 ms | 1.595 ms | 1.595 ms | 1.592 ms | 1.338 ms | 1.284 ms | 1.282 ms | 1.342 ms | — | — | 1.016 ms | 99.181 μs |
| weighted_inner vec | Float64 128^3 | 13.342 ms | 13.467 ms | 13.435 ms | 13.474 ms | 10.903 ms | 10.889 ms | 10.885 ms | 10.936 ms | — | — | 1.475 ms | 170.192 μs |
| weighted_inner vec | Float64 256^3 | 106.185 ms | 107.134 ms | 106.782 ms | 107.247 ms | 85.750 ms | 85.740 ms | 85.753 ms | 85.955 ms | — | — | 5.299 ms | 1.075 ms |
| weighted_inner vec | Float64 512^3 | 839.428 ms | 849.395 ms | 847.598 ms | 850.121 ms | 680.557 ms | 681.377 ms | 681.191 ms | 681.869 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.679 ms | 1.690 ms | 1.687 ms | 1.687 ms | 1.352 ms | 1.353 ms | 1.415 ms | 1.415 ms | — | — | 1.028 ms | 99.561 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.348 ms | 12.463 ms | 12.439 ms | 12.347 ms | 10.368 ms | 10.364 ms | 10.358 ms | 10.386 ms | — | — | 1.435 ms | 156.992 μs |
| weighted_inner vec.vec | Float32 256^3 | 97.135 ms | 97.591 ms | 97.453 ms | 96.992 ms | 81.351 ms | 81.619 ms | 81.386 ms | 81.722 ms | — | — | 4.277 ms | 834.831 μs |
| weighted_inner vec.vec | Float32 512^3 | 769.535 ms | 774.431 ms | 777.825 ms | 771.400 ms | 646.322 ms | 647.232 ms | 647.402 ms | 647.589 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.593 ms | 1.598 ms | 1.599 ms | 1.592 ms | 1.338 ms | 1.283 ms | 1.289 ms | 1.353 ms | — | — | 1.021 ms | 93.401 μs |
| weighted_inner vec.vec | Float64 128^3 | 13.591 ms | 13.697 ms | 13.706 ms | 13.796 ms | 10.943 ms | 10.931 ms | 10.918 ms | 10.939 ms | — | — | 1.517 ms | 260.102 μs |
| weighted_inner vec.vec | Float64 256^3 | 107.934 ms | 108.859 ms | 109.570 ms | 109.514 ms | 86.026 ms | 86.096 ms | 85.923 ms | 86.087 ms | — | — | 5.311 ms | 1.545 ms |
| weighted_inner vec.vec | Float64 512^3 | 852.141 ms | 862.464 ms | 861.115 ms | 866.634 ms | 683.508 ms | 682.615 ms | 779.574 ms | 682.983 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.688 ms | 1.705 ms | 1.690 ms | 1.695 ms | 1.361 ms | 1.405 ms | 1.511 ms | 1.473 ms | — | — | 1.034 ms | 96.841 μs |

