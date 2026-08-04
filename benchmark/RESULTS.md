# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-07-30 at commit `1f423d26` on Julia 1.12.6, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–256³) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The pre-swap archive columns (GTX 1070, RX 6700 XT) keep their pre-rewrite measurements — retired hardware is not re-swept; every live column (both CPUs, RX 7900 XTX, RTX 5070 Ti) is measured at the decision-38/39 rewrite. A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field. Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `1f423d26 @ 2026-07-30`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI; `48b6254a @ 2026-07-22`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8; `5934a78c @ 2026-07-22`: GPU 7900XTX; unstamped (vintage in the prose above): GPU 1070, GPU 6700XT. ~10% jitter.

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 4.029 ms | 2.979 ms | 2.144 ms | 2.286 ms | 2.719 ms | 1.529 ms | 816.199 μs | 523.606 μs | — | — | — | — |
| to_physical scalar measure | Float32 256^3 | 70.669 ms | 39.135 ms | 41.008 ms | 38.313 ms | 33.314 ms | 19.359 ms | 13.998 ms | 11.961 ms | — | — | — | — |
| to_physical scalar measure | Float32 512^3 | — | — | — | — | 290.357 ms | 190.408 ms | 145.316 ms | 132.598 ms | — | — | — | — |
| to_physical scalar measure | Float32 64^3 | 379.762 μs | 239.143 μs | 166.345 μs | 174.205 μs | 275.882 μs | 160.891 μs | 95.931 μs | 71.381 μs | — | — | — | — |
| to_physical scalar measure | Float64 128^3 | 6.339 ms | 5.666 ms | 5.246 ms | 4.657 ms | 3.812 ms | 2.355 ms | 1.445 ms | 1.133 ms | — | — | — | — |
| to_physical scalar measure | Float64 256^3 | 130.934 ms | 77.228 ms | 81.269 ms | 80.228 ms | 67.871 ms | 44.984 ms | 33.328 ms | 44.432 ms | — | — | — | — |
| to_physical scalar measure | Float64 512^3 | — | — | — | — | 867.233 ms | 583.481 ms | 455.127 ms | 407.885 ms | — | — | — | — |
| to_physical scalar measure | Float64 64^3 | 550.138 μs | 384.916 μs | 254.230 μs | 269.289 μs | 366.973 μs | 208.662 μs | 125.801 μs | 101.161 μs | — | — | — | — |
| to_physical scalar | Float32 128^3 | 5.090 ms | 3.355 ms | 2.501 ms | 2.307 ms | 4.557 ms | 2.351 ms | 1.310 ms | 785.619 μs | 788.067 μs | 2.421 ms | 1.261 ms | 122.381 μs |
| to_physical scalar | Float32 256^3 | 121.444 ms | 68.555 ms | 51.504 ms | 42.019 ms | 169.808 ms | 88.208 ms | 47.346 ms | 27.478 ms | — | 7.945 ms | 2.307 ms | 1.088 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | 1.963 s | 1.024 s | 555.571 ms | 324.554 ms | — | — | 13.398 ms | — |
| to_physical scalar | Float32 64^3 | 393.312 μs | 254.738 μs | 177.742 μs | 169.864 μs | 314.573 μs | 175.871 μs | 102.721 μs | 70.680 μs | 124.402 μs | 1.497 ms | 1.071 ms | 113.681 μs |
| to_physical scalar | Float64 128^3 | 8.120 ms | 5.823 ms | 4.940 ms | 4.470 ms | 10.290 ms | 5.357 ms | 2.986 ms | 1.828 ms | 1.905 ms | 3.750 ms | 1.646 ms | 493.385 μs |
| to_physical scalar | Float64 256^3 | 153.418 ms | 86.677 ms | 84.769 ms | 78.209 ms | 83.832 ms | 50.177 ms | 35.812 ms | 38.930 ms | — | 14.463 ms | 5.748 ms | 3.854 ms |
| to_physical scalar | Float64 512^3 | — | — | — | — | 945.915 ms | 624.326 ms | 457.700 ms | 416.609 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 702.253 μs | 432.399 μs | 307.892 μs | 258.256 μs | 538.135 μs | 290.303 μs | 166.412 μs | 120.411 μs | 331.873 μs | 1.784 ms | 992.328 μs | 116.131 μs |
| to_physical vector measure | Float32 128^3 | 12.766 ms | 9.673 ms | 8.916 ms | 7.915 ms | 9.104 ms | 6.073 ms | 3.640 ms | 3.233 ms | — | — | — | — |
| to_physical vector measure | Float32 256^3 | 214.079 ms | 158.244 ms | 131.321 ms | 124.027 ms | 119.963 ms | 80.532 ms | 55.906 ms | 49.005 ms | — | — | — | — |
| to_physical vector measure | Float32 512^3 | — | — | — | — | 1.394 s | 975.301 ms | 709.628 ms | 655.126 ms | — | — | — | — |
| to_physical vector measure | Float32 64^3 | 1.243 ms | 846.687 μs | 565.090 μs | 477.502 μs | 862.927 μs | 497.535 μs | 291.663 μs | 206.272 μs | — | — | — | — |
| to_physical vector measure | Float64 128^3 | 39.710 ms | 19.225 ms | 24.054 ms | 28.588 ms | 22.171 ms | 17.516 ms | 13.835 ms | 13.123 ms | — | — | — | — |
| to_physical vector measure | Float64 256^3 | 394.501 ms | 287.104 ms | 246.423 ms | 233.583 ms | 314.639 ms | 225.714 ms | 157.303 ms | 159.891 ms | — | — | — | — |
| to_physical vector measure | Float64 512^3 | — | — | — | — | 2.532 s | 1.769 s | 1.359 s | 1.183 s | — | — | — | — |
| to_physical vector measure | Float64 64^3 | 2.216 ms | 1.775 ms | 1.270 ms | 1.164 ms | 1.155 ms | 693.587 μs | 421.284 μs | 324.383 μs | — | — | — | — |
| to_physical vector | Float32 128^3 | 15.103 ms | 11.836 ms | 8.416 ms | 7.502 ms | 14.514 ms | 10.483 ms | 5.464 ms | 3.893 ms | 2.507 ms | 4.595 ms | 1.724 ms | 308.573 μs |
| to_physical vector | Float32 256^3 | 365.291 ms | 269.022 ms | 173.624 ms | 151.640 ms | 534.913 ms | 358.921 ms | 192.540 ms | 136.306 ms | — | 14.844 ms | 5.773 ms | 3.473 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | 6.339 s | 4.305 s | 2.320 s | 1.657 s | — | — | 51.336 ms | — |
| to_physical vector | Float32 64^3 | 1.306 ms | 1.045 ms | 596.992 μs | 550.376 μs | 1.011 ms | 681.647 μs | 319.343 μs | 219.772 μs | 380.054 μs | 1.776 ms | 1.186 ms | 111.701 μs |
| to_physical vector | Float64 128^3 | 46.428 ms | 20.507 ms | 26.548 ms | 27.522 ms | 41.555 ms | 29.192 ms | 19.289 ms | 16.095 ms | 5.630 ms | 8.090 ms | 2.788 ms | 1.473 ms |
| to_physical vector | Float64 256^3 | 460.818 ms | 358.235 ms | 260.213 ms | 241.545 ms | 352.403 ms | 271.591 ms | 169.406 ms | 157.312 ms | — | 22.812 ms | 13.720 ms | 11.373 ms |
| to_physical vector | Float64 512^3 | — | — | — | — | 2.818 s | 2.148 s | 1.420 s | 1.253 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.619 ms | 2.147 ms | 1.646 ms | 1.216 ms | 1.646 ms | 1.133 ms | 574.815 μs | 420.524 μs | 811.437 μs | 2.301 ms | 1.271 ms | 211.802 μs |
| to_spectral scalar measure | Float32 128^3 | 3.676 ms | 2.364 ms | 1.542 ms | 1.608 ms | 2.744 ms | 1.435 ms | 774.239 μs | 469.526 μs | — | — | — | — |
| to_spectral scalar measure | Float32 256^3 | 64.792 ms | 32.427 ms | 35.643 ms | 32.348 ms | 33.637 ms | 19.808 ms | 12.924 ms | 10.178 ms | — | — | — | — |
| to_spectral scalar measure | Float32 512^3 | — | — | — | — | 313.404 ms | 182.922 ms | 117.193 ms | 104.146 ms | — | — | — | — |
| to_spectral scalar measure | Float32 64^3 | 365.235 μs | 209.243 μs | 132.354 μs | 137.319 μs | 276.653 μs | 147.592 μs | 89.151 μs | 56.610 μs | — | — | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.417 ms | 4.397 ms | 3.789 ms | 3.542 ms | 4.135 ms | 2.318 ms | 1.342 ms | 905.199 μs | — | — | — | — |
| to_spectral scalar measure | Float64 256^3 | 125.027 ms | 67.875 ms | 71.203 ms | 65.713 ms | 62.807 ms | 38.546 ms | 25.915 ms | 32.522 ms | — | — | — | — |
| to_spectral scalar measure | Float64 512^3 | — | — | — | — | 777.022 ms | 503.060 ms | 389.366 ms | 331.564 ms | — | — | — | — |
| to_spectral scalar measure | Float64 64^3 | 488.909 μs | 307.927 μs | 233.393 μs | 155.459 μs | 341.573 μs | 192.692 μs | 113.241 μs | 84.591 μs | — | — | — | — |
| to_spectral scalar | Float32 128^3 | 4.631 ms | 2.783 ms | 1.829 ms | 1.359 ms | 4.612 ms | 2.412 ms | 1.296 ms | 719.418 μs | 488.254 μs | 2.072 ms | 1.113 ms | 94.281 μs |
| to_spectral scalar | Float32 256^3 | 116.450 ms | 64.693 ms | 48.096 ms | 36.889 ms | 168.406 ms | 86.464 ms | 46.277 ms | 26.213 ms | — | 5.009 ms | 1.905 ms | 734.818 μs |
| to_spectral scalar | Float32 512^3 | — | — | — | — | 1.923 s | 978.002 ms | 514.798 ms | 292.378 ms | — | — | 9.591 ms | — |
| to_spectral scalar | Float32 64^3 | 372.359 μs | 214.769 μs | 131.392 μs | 113.455 μs | 305.093 μs | 165.242 μs | 92.491 μs | 58.701 μs | 89.181 μs | 1.538 ms | 1.110 ms | 76.461 μs |
| to_spectral scalar | Float64 128^3 | 7.266 ms | 5.156 ms | 3.900 ms | 3.492 ms | 10.338 ms | 5.583 ms | 2.833 ms | 1.591 ms | 1.501 ms | 3.125 ms | 1.651 ms | 426.534 μs |
| to_spectral scalar | Float64 256^3 | 174.719 ms | 98.673 ms | 79.881 ms | 67.152 ms | 171.947 ms | 91.717 ms | 51.901 ms | 46.898 ms | — | 12.871 ms | 5.179 ms | 3.127 ms |
| to_spectral scalar | Float64 512^3 | — | — | — | — | 1.733 s | 970.837 ms | 599.415 ms | 435.487 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 660.845 μs | 375.644 μs | 246.524 μs | 187.733 μs | 503.364 μs | 275.273 μs | 152.512 μs | 96.871 μs | 265.683 μs | 1.745 ms | 1.077 ms | 108.401 μs |
| to_spectral vector measure | Float32 128^3 | 11.048 ms | 7.840 ms | 6.309 ms | 5.676 ms | 10.046 ms | 6.155 ms | 3.638 ms | 3.122 ms | — | — | — | — |
| to_spectral vector measure | Float32 256^3 | 194.942 ms | 138.599 ms | 108.318 ms | 104.246 ms | 116.093 ms | 72.180 ms | 45.865 ms | 40.829 ms | — | — | — | — |
| to_spectral vector measure | Float32 512^3 | — | — | — | — | 1.394 s | 932.115 ms | 608.744 ms | 523.351 ms | — | — | — | — |
| to_spectral vector measure | Float32 64^3 | 1.133 ms | 709.014 μs | 489.066 μs | 410.465 μs | 851.237 μs | 492.105 μs | 253.533 μs | 166.552 μs | — | — | — | — |
| to_spectral vector measure | Float64 128^3 | 36.748 ms | 15.038 ms | 18.304 ms | 13.894 ms | 23.110 ms | 17.810 ms | 13.436 ms | 7.753 ms | — | — | — | — |
| to_spectral vector measure | Float64 256^3 | 378.151 ms | 266.528 ms | 209.729 ms | 202.722 ms | 287.264 ms | 200.182 ms | 137.029 ms | 129.129 ms | — | — | — | — |
| to_spectral vector measure | Float64 512^3 | — | — | — | — | 2.263 s | 1.532 s | 1.137 s | 993.111 ms | — | — | — | — |
| to_spectral vector measure | Float64 64^3 | 1.673 ms | 1.521 ms | 887.037 μs | 648.760 μs | 1.054 ms | 626.786 μs | 352.453 μs | 257.583 μs | — | — | — | — |
| to_spectral vector | Float32 128^3 | 14.075 ms | 9.864 ms | 6.814 ms | 5.884 ms | 14.841 ms | 10.647 ms | 5.041 ms | 3.457 ms | 1.355 ms | 3.183 ms | 1.354 ms | 190.642 μs |
| to_spectral vector | Float32 256^3 | 353.409 ms | 258.328 ms | 153.782 ms | 128.389 ms | 522.181 ms | 349.257 ms | 178.169 ms | 126.784 ms | — | 11.819 ms | 3.512 ms | 2.221 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | 6.280 s | 4.291 s | 2.238 s | 1.571 s | — | — | 20.305 ms | — |
| to_spectral vector | Float32 64^3 | 1.296 ms | 931.449 μs | 509.295 μs | 432.093 μs | 964.199 μs | 655.487 μs | 291.702 μs | 182.612 μs | 230.522 μs | 1.566 ms | 924.065 μs | 85.581 μs |
| to_spectral vector | Float64 128^3 | 43.494 ms | 18.891 ms | 23.457 ms | 13.411 ms | 41.778 ms | 30.919 ms | 18.873 ms | 11.309 ms | 4.144 ms | 6.538 ms | 2.420 ms | 1.173 ms |
| to_spectral vector | Float64 256^3 | 515.584 ms | 385.138 ms | 244.471 ms | 223.678 ms | 632.722 ms | 450.031 ms | 239.415 ms | 197.489 ms | — | 20.041 ms | 11.730 ms | 9.212 ms |
| to_spectral vector | Float64 512^3 | — | — | — | — | 5.117 s | 3.609 s | 2.024 s | 1.595 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.288 ms | 1.711 ms | 1.039 ms | 825.169 μs | 1.546 ms | 1.068 ms | 520.105 μs | 343.703 μs | 596.836 μs | 2.151 ms | 1.215 ms | 201.482 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 415.446 μs | 232.867 μs | 171.971 μs | 72.717 μs | 161.991 μs | 86.351 μs | 43.641 μs | 35.950 μs | 351.303 μs | 1.943 ms | 1.146 ms | 74.700 μs |
| add! scalar | Float32 256^3 | 8.457 ms | 7.574 ms | 5.893 ms | 5.483 ms | 3.560 ms | 3.094 ms | 2.717 ms | 2.832 ms | — | 6.480 ms | 1.935 ms | 332.504 μs |
| add! scalar | Float32 512^3 | — | — | — | — | 40.433 ms | 36.657 ms | 36.703 ms | 37.196 ms | — | — | 7.478 ms | — |
| add! scalar | Float32 64^3 | 43.141 μs | 21.824 μs | 10.651 μs | 8.520 μs | 22.310 μs | 12.410 μs | 7.047 μs | 6.653 μs | 85.391 μs | 1.599 ms | 1.040 ms | 54.461 μs |
| add! scalar | Float64 128^3 | 1.551 ms | 1.347 ms | 1.009 ms | 866.257 μs | 325.543 μs | 163.582 μs | 85.761 μs | 72.411 μs | 354.693 μs | 2.024 ms | 1.185 ms | 89.251 μs |
| add! scalar | Float64 256^3 | 17.701 ms | 15.946 ms | 12.391 ms | 11.679 ms | 10.295 ms | 8.738 ms | 8.430 ms | 8.510 ms | — | 5.550 ms | 1.863 ms | 561.306 μs |
| add! scalar | Float64 512^3 | — | — | — | — | 83.817 ms | 72.956 ms | 73.324 ms | 74.217 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 85.390 μs | 49.484 μs | 21.892 μs | 16.987 μs | 40.251 μs | 23.721 μs | 12.030 μs | 9.670 μs | 83.741 μs | 1.494 ms | 1.042 ms | 54.521 μs |
| combine! vec | Float32 128^3 | 2.791 ms | 2.491 ms | 1.937 ms | 1.731 ms | 628.886 μs | 312.733 μs | 162.492 μs | 115.072 μs | — | — | 1.460 ms | 189.302 μs |
| combine! vec | Float32 256^3 | 26.616 ms | 24.004 ms | 18.893 ms | 17.671 ms | 13.835 ms | 13.569 ms | 13.526 ms | 12.998 ms | — | — | 4.150 ms | 1.020 ms |
| combine! vec | Float32 512^3 | — | — | — | — | 116.808 ms | 109.807 ms | 110.747 ms | 110.940 ms | — | — | 19.880 ms | — |
| combine! vec | Float32 64^3 | 129.345 μs | 71.185 μs | 38.072 μs | 19.846 μs | 65.031 μs | 37.930 μs | 20.400 μs | 14.540 μs | — | — | 1.124 ms | 64.701 μs |
| combine! vec | Float64 128^3 | 6.186 ms | 5.637 ms | 4.316 ms | 4.084 ms | 2.192 ms | 1.861 ms | 1.553 ms | 1.488 ms | — | — | 1.695 ms | 243.262 μs |
| combine! vec | Float64 256^3 | 53.020 ms | 48.164 ms | 37.890 ms | 35.457 ms | 28.460 ms | 26.583 ms | 26.925 ms | 27.344 ms | — | — | 4.922 ms | 1.581 ms |
| combine! vec | Float64 512^3 | — | — | — | — | 225.105 ms | 209.288 ms | 220.968 ms | 221.935 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 269.387 μs | 146.932 μs | 80.411 μs | 45.637 μs | 123.331 μs | 64.820 μs | 34.290 μs | 25.931 μs | — | — | 1.119 ms | 84.621 μs |
| cross! | Float32 128^3 | 3.081 ms | 2.621 ms | 2.296 ms | 2.180 ms | 1.917 ms | 991.870 μs | 494.735 μs | 248.852 μs | 1.223 ms | 3.445 ms | 1.087 ms | 131.261 μs |
| cross! | Float32 256^3 | 28.931 ms | 26.586 ms | 24.325 ms | 23.702 ms | 23.213 ms | 14.849 ms | 12.369 ms | 12.505 ms | — | 14.690 ms | 1.775 ms | 835.049 μs |
| cross! | Float32 512^3 | — | — | — | — | 191.740 ms | 120.824 ms | 111.279 ms | 111.863 ms | — | — | 7.558 ms | — |
| cross! | Float32 64^3 | 262.350 μs | 129.860 μs | 72.659 μs | 39.588 μs | 233.682 μs | 118.201 μs | 59.331 μs | 32.530 μs | 219.582 μs | 1.665 ms | 1.031 ms | 55.961 μs |
| cross! | Float64 128^3 | 6.532 ms | 6.049 ms | 5.442 ms | 5.440 ms | 3.759 ms | 2.301 ms | 1.554 ms | 1.475 ms | 1.263 ms | 2.603 ms | 1.367 ms | 249.672 μs |
| cross! | Float64 256^3 | 58.605 ms | 53.033 ms | 49.389 ms | 46.968 ms | 45.115 ms | 29.086 ms | 27.149 ms | 27.471 ms | — | 15.625 ms | 2.733 ms | 1.594 ms |
| cross! | Float64 512^3 | — | — | — | — | 318.929 ms | 216.028 ms | 222.603 ms | 224.905 ms | — | — | — | — |
| cross! | Float64 64^3 | 373.469 μs | 187.020 μs | 101.539 μs | 53.528 μs | 225.502 μs | 115.451 μs | 63.640 μs | 35.910 μs | 216.592 μs | 1.846 ms | 1.103 ms | 74.161 μs |
| det! tensor | Float32 128^3 | 3.660 ms | 2.587 ms | 2.160 ms | 1.966 ms | 2.194 ms | 1.128 ms | 564.097 μs | 287.433 μs | — | — | 1.218 ms | 167.052 μs |
| det! tensor | Float32 256^3 | 36.447 ms | 25.949 ms | 23.192 ms | 21.245 ms | 28.220 ms | 15.159 ms | 12.078 ms | 11.937 ms | — | — | 2.219 ms | 897.719 μs |
| det! tensor | Float32 512^3 | — | — | — | — | 218.590 ms | 124.227 ms | 104.312 ms | 102.792 ms | — | — | 9.408 ms | — |
| det! tensor | Float32 64^3 | 361.565 μs | 186.619 μs | 83.056 μs | 46.689 μs | 250.192 μs | 128.592 μs | 66.671 μs | 35.570 μs | — | — | 966.709 μs | 64.300 μs |
| det! tensor | Float64 128^3 | 6.753 ms | 5.973 ms | 4.837 ms | 4.566 ms | 4.002 ms | 2.402 ms | 1.694 ms | 1.609 ms | — | — | 1.460 ms | 262.493 μs |
| det! tensor | Float64 256^3 | 54.980 ms | 52.857 ms | 43.163 ms | 39.883 ms | 46.067 ms | 29.098 ms | 25.601 ms | 26.267 ms | — | — | 2.941 ms | 1.849 ms |
| det! tensor | Float64 512^3 | — | — | — | — | 384.148 ms | 238.812 ms | 207.937 ms | 210.680 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 363.147 μs | 220.005 μs | 110.514 μs | 60.662 μs | 259.122 μs | 151.271 μs | 67.270 μs | 42.540 μs | — | — | 1.071 ms | 67.810 μs |
| dot! vec.vec | Float32 128^3 | 2.899 ms | 1.731 ms | 1.349 ms | 1.223 ms | 2.475 ms | 1.245 ms | 623.467 μs | 327.094 μs | 538.855 μs | 2.430 ms | 1.239 ms | 114.251 μs |
| dot! vec.vec | Float32 256^3 | 24.982 ms | 18.857 ms | 15.827 ms | 15.018 ms | 25.617 ms | 13.795 ms | 8.156 ms | 8.028 ms | — | 9.651 ms | 2.506 ms | 676.917 μs |
| dot! vec.vec | Float32 512^3 | — | — | — | — | 195.663 ms | 95.246 ms | 75.923 ms | 75.738 ms | — | — | 11.342 ms | — |
| dot! vec.vec | Float32 64^3 | 336.093 μs | 201.695 μs | 106.726 μs | 61.308 μs | 308.453 μs | 159.052 μs | 81.570 μs | 44.000 μs | 112.901 μs | 1.663 ms | 1.107 ms | 69.140 μs |
| dot! vec.vec | Float64 128^3 | 4.596 ms | 3.946 ms | 3.317 ms | 3.108 ms | 3.617 ms | 1.756 ms | 901.840 μs | 576.096 μs | 618.906 μs | 2.505 ms | 1.223 ms | 185.462 μs |
| dot! vec.vec | Float64 256^3 | 44.072 ms | 36.289 ms | 30.450 ms | 28.480 ms | 37.263 ms | 22.100 ms | 17.906 ms | 19.053 ms | — | 9.784 ms | 2.819 ms | 1.211 ms |
| dot! vec.vec | Float64 512^3 | — | — | — | — | 260.800 ms | 150.311 ms | 149.974 ms | 151.472 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 342.485 μs | 207.767 μs | 108.330 μs | 66.523 μs | 319.003 μs | 164.271 μs | 82.151 μs | 44.601 μs | 127.611 μs | 1.656 ms | 1.019 ms | 59.521 μs |
| map!(+) vec | Float32 128^3 | — | — | — | — | 1.719 ms | 828.478 μs | 413.825 μs | 213.712 μs | — | — | — | 119.931 μs |
| map!(+) vec | Float32 256^3 | — | — | — | — | 21.563 ms | 14.181 ms | 12.366 ms | 12.559 ms | — | — | — | 840.478 μs |
| map!(+) vec | Float32 512^3 | — | — | — | — | 179.456 ms | 118.625 ms | 111.349 ms | 111.905 ms | — | — | — | — |
| map!(+) vec | Float32 64^3 | — | — | — | — | 199.332 μs | 96.470 μs | 48.171 μs | 27.230 μs | — | — | — | 60.630 μs |
| map!(+) vec | Float64 128^3 | — | — | — | — | 3.667 ms | 2.235 ms | 1.523 ms | 1.482 ms | — | — | — | 253.222 μs |
| map!(+) vec | Float64 256^3 | — | — | — | — | 40.880 ms | 28.369 ms | 27.179 ms | 27.540 ms | — | — | — | 1.599 ms |
| map!(+) vec | Float64 512^3 | — | — | — | — | 308.407 ms | 215.344 ms | 221.694 ms | 224.781 ms | — | — | — | — |
| map!(+) vec | Float64 64^3 | — | — | — | — | 175.182 μs | 94.851 μs | 48.481 μs | 33.061 μs | — | — | — | 77.341 μs |
| map!(det) tensor | Float32 128^3 | — | — | — | — | 2.184 ms | 1.129 ms | 564.066 μs | 281.773 μs | — | — | — | 176.532 μs |
| map!(det) tensor | Float32 256^3 | — | — | — | — | 27.906 ms | 15.138 ms | 12.126 ms | 11.940 ms | — | — | — | 981.730 μs |
| map!(det) tensor | Float32 512^3 | — | — | — | — | 222.719 ms | 123.571 ms | 104.084 ms | 102.910 ms | — | — | — | — |
| map!(det) tensor | Float32 64^3 | — | — | — | — | 249.662 μs | 127.792 μs | 65.301 μs | 36.810 μs | — | — | — | 66.031 μs |
| map!(det) tensor | Float64 128^3 | — | — | — | — | 4.028 ms | 2.394 ms | 1.689 ms | 1.606 ms | — | — | — | 269.463 μs |
| map!(det) tensor | Float64 256^3 | — | — | — | — | 45.584 ms | 28.890 ms | 25.580 ms | 26.204 ms | — | — | — | 1.855 ms |
| map!(det) tensor | Float64 512^3 | — | — | — | — | 373.981 ms | 231.320 ms | 207.273 ms | 210.998 ms | — | — | — | — |
| map!(det) tensor | Float64 64^3 | — | — | — | — | 251.462 μs | 129.692 μs | 66.301 μs | 41.111 μs | — | — | — | 71.401 μs |
| mul! tensor.vec | Float32 128^3 | 5.241 ms | 4.508 ms | 4.097 ms | 3.891 ms | 3.378 ms | 1.893 ms | 1.033 ms | 763.609 μs | 1.525 ms | 4.295 ms | 1.202 ms | 199.732 μs |
| mul! tensor.vec | Float32 256^3 | 56.838 ms | 41.730 ms | 39.368 ms | 37.470 ms | 32.286 ms | 23.426 ms | 21.484 ms | 20.809 ms | — | 16.892 ms | 2.504 ms | 1.323 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | 352.044 ms | 220.083 ms | 178.846 ms | 175.885 ms | — | — | 12.936 ms | — |
| mul! tensor.vec | Float32 64^3 | 628.537 μs | 242.475 μs | 121.446 μs | 68.588 μs | 372.983 μs | 212.192 μs | 107.251 μs | 60.270 μs | 255.702 μs | 1.882 ms | 1.051 ms | 63.641 μs |
| mul! tensor.vec | Float64 128^3 | 11.484 ms | 10.231 ms | 9.209 ms | 9.025 ms | 7.054 ms | 5.391 ms | 4.332 ms | 4.267 ms | 1.748 ms | 4.757 ms | 1.469 ms | 379.374 μs |
| mul! tensor.vec | Float64 256^3 | 90.503 ms | 85.167 ms | 77.262 ms | 74.028 ms | 63.052 ms | 50.573 ms | 43.958 ms | 43.452 ms | — | 17.818 ms | 3.896 ms | 2.567 ms |
| mul! tensor.vec | Float64 512^3 | — | — | — | — | 544.709 ms | 371.075 ms | 350.961 ms | 351.327 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 695.993 μs | 473.800 μs | 359.566 μs | 211.291 μs | 377.593 μs | 217.982 μs | 108.981 μs | 59.221 μs | 280.183 μs | 1.951 ms | 1.082 ms | 78.361 μs |
| norm! vec | Float32 128^3 | 746.619 μs | 599.150 μs | 478.282 μs | 359.445 μs | 217.192 μs | 120.031 μs | 76.961 μs | 52.890 μs | 411.304 μs | 2.110 ms | 1.077 ms | 83.591 μs |
| norm! vec | Float32 256^3 | 10.798 ms | 10.148 ms | 8.212 ms | 7.831 ms | 5.247 ms | 4.320 ms | 4.089 ms | 4.232 ms | — | 7.304 ms | 2.143 ms | 411.304 μs |
| norm! vec | Float32 512^3 | — | — | — | — | 53.332 ms | 46.639 ms | 46.564 ms | 46.803 ms | — | — | 7.958 ms | — |
| norm! vec | Float32 64^3 | 54.472 μs | 38.606 μs | 20.836 μs | 16.505 μs | 31.070 μs | 20.490 μs | 12.580 μs | 11.280 μs | 100.251 μs | 1.526 ms | 1.029 ms | 59.200 μs |
| norm! vec | Float64 128^3 | 2.313 ms | 2.021 ms | 1.631 ms | 1.458 ms | 485.315 μs | 247.782 μs | 127.262 μs | 102.991 μs | 463.344 μs | 1.434 ms | 1.433 ms | 169.802 μs |
| norm! vec | Float64 256^3 | 22.327 ms | 20.362 ms | 16.905 ms | 15.982 ms | 11.858 ms | 10.246 ms | 10.232 ms | 10.532 ms | — | 9.850 ms | 3.294 ms | 720.158 μs |
| norm! vec | Float64 512^3 | — | — | — | — | 107.778 ms | 90.328 ms | 91.829 ms | 93.173 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 160.911 μs | 91.195 μs | 50.848 μs | 32.368 μs | 56.521 μs | 38.420 μs | 21.000 μs | 16.371 μs | 101.231 μs | 1.681 ms | 1.117 ms | 61.231 μs |
| tr! tensor | Float32 128^3 | 714.866 μs | 548.546 μs | 465.762 μs | 349.269 μs | 215.122 μs | 114.071 μs | 62.081 μs | 51.491 μs | — | — | 1.021 ms | 84.731 μs |
| tr! tensor | Float32 256^3 | 10.668 ms | 9.839 ms | 8.090 ms | 7.701 ms | 5.150 ms | 4.391 ms | 4.312 ms | 4.367 ms | — | — | 1.859 ms | 386.263 μs |
| tr! tensor | Float32 512^3 | — | — | — | — | 51.621 ms | 45.326 ms | 46.282 ms | 46.863 ms | — | — | 8.577 ms | — |
| tr! tensor | Float32 64^3 | 53.777 μs | 34.817 μs | 16.681 μs | 14.213 μs | 27.231 μs | 18.770 μs | 10.930 μs | 9.430 μs | — | — | 1.108 ms | 70.730 μs |
| tr! tensor | Float64 128^3 | 2.278 ms | 1.979 ms | 1.580 ms | 1.405 ms | 458.074 μs | 244.472 μs | 122.471 μs | 99.231 μs | — | — | 1.153 ms | 114.851 μs |
| tr! tensor | Float64 256^3 | 21.191 ms | 19.901 ms | 16.409 ms | 15.480 ms | 11.598 ms | 10.520 ms | 10.541 ms | 10.765 ms | — | — | 2.035 ms | 729.157 μs |
| tr! tensor | Float64 512^3 | — | — | — | — | 95.824 ms | 90.538 ms | 93.056 ms | 94.142 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 107.137 μs | 64.410 μs | 34.513 μs | 22.760 μs | 53.000 μs | 35.281 μs | 19.000 μs | 14.290 μs | — | — | 1.004 ms | 64.821 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.644 ms | 2.884 ms | 1.570 ms | 1.284 ms | 3.230 ms | 1.663 ms | 835.449 μs | 428.225 μs | 697.807 μs | 2.544 ms | 1.114 ms | 87.461 μs |
| curl! vec->vec | Float32 256^3 | 47.565 ms | 23.207 ms | 18.167 ms | 17.606 ms | 26.769 ms | 13.734 ms | 8.533 ms | 8.547 ms | — | 10.865 ms | 1.562 ms | 597.626 μs |
| curl! vec->vec | Float32 512^3 | — | — | — | — | 205.138 ms | 105.634 ms | 83.021 ms | 83.726 ms | — | — | 6.384 ms | — |
| curl! vec->vec | Float32 64^3 | 715.869 μs | 361.298 μs | 185.059 μs | 97.663 μs | 413.354 μs | 216.882 μs | 111.581 μs | 60.071 μs | 182.902 μs | 1.646 ms | 1.026 ms | 61.871 μs |
| curl! vec->vec | Float64 128^3 | 5.732 ms | 4.247 ms | 3.988 ms | 3.859 ms | 3.692 ms | 1.892 ms | 931.060 μs | 520.286 μs | 824.588 μs | 3.153 ms | 1.535 ms | 198.862 μs |
| curl! vec->vec | Float64 256^3 | 48.543 ms | 38.387 ms | 36.437 ms | 35.207 ms | 33.109 ms | 20.104 ms | 19.315 ms | 20.602 ms | — | 13.647 ms | 3.147 ms | 1.115 ms |
| curl! vec->vec | Float64 512^3 | — | — | — | — | 251.573 ms | 167.995 ms | 164.389 ms | 166.473 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 685.445 μs | 351.104 μs | 180.555 μs | 96.016 μs | 466.594 μs | 229.212 μs | 120.171 μs | 64.121 μs | 186.242 μs | 1.786 ms | 1.155 ms | 79.460 μs |
| divergence! vec->scalar | Float32 128^3 | 3.583 ms | 1.379 ms | 726.007 μs | 414.664 μs | 3.348 ms | 1.109 ms | 573.077 μs | 286.123 μs | 326.353 μs | 1.957 ms | 1.144 ms | 81.891 μs |
| divergence! vec->scalar | Float32 256^3 | 29.383 ms | 11.815 ms | 9.639 ms | 9.114 ms | 26.806 ms | 8.940 ms | 4.550 ms | 4.140 ms | — | 5.523 ms | 1.734 ms | 404.535 μs |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | 211.333 ms | 69.588 ms | 46.343 ms | 46.828 ms | — | — | 6.985 ms | — |
| divergence! vec->scalar | Float32 64^3 | 427.482 μs | 176.505 μs | 93.067 μs | 51.431 μs | 434.363 μs | 151.841 μs | 78.231 μs | 42.811 μs | 93.900 μs | 1.537 ms | 971.404 μs | 76.351 μs |
| divergence! vec->scalar | Float64 128^3 | 3.927 ms | 2.101 ms | 1.724 ms | 1.552 ms | 3.353 ms | 1.078 ms | 538.056 μs | 277.943 μs | 407.644 μs | 2.306 ms | 1.190 ms | 129.222 μs |
| divergence! vec->scalar | Float64 256^3 | 32.045 ms | 22.048 ms | 17.831 ms | 16.405 ms | 27.411 ms | 11.071 ms | 10.324 ms | 10.266 ms | — | 7.090 ms | 2.578 ms | 734.518 μs |
| divergence! vec->scalar | Float64 512^3 | — | — | — | — | 213.026 ms | 95.602 ms | 93.146 ms | 93.516 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 444.337 μs | 163.080 μs | 87.120 μs | 53.950 μs | 436.764 μs | 139.451 μs | 72.541 μs | 40.961 μs | 103.111 μs | 344.869 μs | 982.625 μs | 72.460 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.411 ms | 1.797 ms | 988.567 μs | 683.645 μs | 4.930 ms | 2.044 ms | 1.048 ms | 525.066 μs | — | — | 1.230 ms | 92.591 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 36.347 ms | 14.813 ms | 12.158 ms | 11.437 ms | 39.707 ms | 16.208 ms | 8.140 ms | 4.256 ms | — | — | 2.109 ms | 401.914 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | — | — | — | — | 312.001 ms | 127.108 ms | 64.486 ms | 46.985 ms | — | — | 7.652 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 539.303 μs | 233.316 μs | 134.678 μs | 71.987 μs | 634.695 μs | 270.403 μs | 139.462 μs | 74.141 μs | — | — | 1.103 ms | 66.421 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.877 ms | 2.753 ms | 2.260 ms | 2.157 ms | 4.947 ms | 1.979 ms | 993.241 μs | 505.425 μs | — | — | 1.365 ms | 182.832 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 39.931 ms | 26.505 ms | 21.953 ms | 20.596 ms | 39.933 ms | 15.858 ms | 10.339 ms | 10.265 ms | — | — | 2.922 ms | 736.367 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | — | — | — | — | 317.746 ms | 126.672 ms | 94.224 ms | 93.553 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 533.393 μs | 216.600 μs | 115.672 μs | 70.444 μs | 638.076 μs | 254.972 μs | 132.891 μs | 71.690 μs | — | — | 1.163 ms | 71.901 μs |
| gradient! scalar->vec | Float32 128^3 | 3.262 ms | 1.702 ms | 880.984 μs | 532.987 μs | 1.967 ms | 974.440 μs | 491.405 μs | 253.163 μs | 560.525 μs | 2.377 ms | 1.076 ms | 76.540 μs |
| gradient! scalar->vec | Float32 256^3 | 26.249 ms | 15.053 ms | 13.785 ms | 13.763 ms | 15.637 ms | 7.832 ms | 5.637 ms | 5.636 ms | — | 7.929 ms | 1.569 ms | 434.374 μs |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | 124.459 ms | 66.560 ms | 64.026 ms | 64.354 ms | — | — | 4.394 ms | — |
| gradient! scalar->vec | Float32 64^3 | 415.585 μs | 221.863 μs | 107.430 μs | 58.414 μs | 247.052 μs | 126.641 μs | 64.621 μs | 34.760 μs | 133.261 μs | 1.681 ms | 1.016 ms | 60.681 μs |
| gradient! scalar->vec | Float64 128^3 | 3.461 ms | 2.907 ms | 2.635 ms | 2.547 ms | 2.070 ms | 990.890 μs | 494.675 μs | 254.283 μs | 605.225 μs | 2.717 ms | 1.313 ms | 180.202 μs |
| gradient! scalar->vec | Float64 256^3 | 32.069 ms | 29.672 ms | 28.081 ms | 27.512 ms | 20.062 ms | 14.782 ms | 14.003 ms | 14.109 ms | — | 10.338 ms | 2.498 ms | 804.248 μs |
| gradient! scalar->vec | Float64 512^3 | — | — | — | — | 160.815 ms | 129.578 ms | 127.482 ms | 127.882 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 368.859 μs | 192.400 μs | 94.043 μs | 56.623 μs | 255.742 μs | 125.772 μs | 63.530 μs | 34.610 μs | 153.172 μs | 1.872 ms | 1.022 ms | 68.671 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.405 ms | 2.303 ms | 1.399 ms | 1.289 ms | 3.412 ms | 1.692 ms | 853.080 μs | 444.515 μs | 1.480 ms | 4.174 ms | 1.196 ms | 95.731 μs |
| helmholtz! vec->vec | Float32 256^3 | 36.655 ms | 19.651 ms | 18.114 ms | 17.670 ms | 28.386 ms | 14.142 ms | 8.521 ms | 8.551 ms | — | 16.637 ms | 1.739 ms | 594.896 μs |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | 218.976 ms | 109.387 ms | 82.938 ms | 83.887 ms | — | — | 6.606 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 558.786 μs | 286.971 μs | 150.825 μs | 78.160 μs | 447.214 μs | 228.343 μs | 115.881 μs | 62.340 μs | 286.333 μs | 1.935 ms | 1.057 ms | 61.321 μs |
| helmholtz! vec->vec | Float64 128^3 | 5.186 ms | 4.220 ms | 3.854 ms | 3.823 ms | 3.876 ms | 1.996 ms | 1.007 ms | 559.196 μs | 1.802 ms | 5.921 ms | 1.598 ms | 238.753 μs |
| helmholtz! vec->vec | Float64 256^3 | 44.813 ms | 38.769 ms | 36.382 ms | 35.180 ms | 34.777 ms | 20.409 ms | 19.362 ms | 19.551 ms | — | 18.240 ms | 3.879 ms | 1.406 ms |
| helmholtz! vec->vec | Float64 512^3 | — | — | — | — | 260.640 ms | 169.478 ms | 164.503 ms | 166.581 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 593.457 μs | 310.953 μs | 156.789 μs | 86.253 μs | 514.485 μs | 256.583 μs | 133.361 μs | 71.771 μs | 342.613 μs | 2.260 ms | 1.218 ms | 82.041 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 6.146 ms | 3.063 ms | 1.840 ms | 1.618 ms | 6.355 ms | 3.162 ms | 1.595 ms | 816.919 μs | — | — | 1.065 ms | 95.591 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 50.158 ms | 24.608 ms | 20.555 ms | 19.673 ms | 50.192 ms | 25.221 ms | 12.626 ms | 8.516 ms | — | — | 1.706 ms | 598.906 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | — | — | — | — | 402.062 ms | 200.660 ms | 101.985 ms | 83.201 ms | — | — | 7.390 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 779.149 μs | 395.970 μs | 200.974 μs | 106.172 μs | 829.368 μs | 423.324 μs | 215.392 μs | 112.571 μs | — | — | 1.107 ms | 69.231 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 6.666 ms | 4.845 ms | 4.468 ms | 4.407 ms | 6.789 ms | 3.542 ms | 1.736 ms | 890.349 μs | — | — | 1.683 ms | 290.813 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 56.105 ms | 43.079 ms | 40.773 ms | 39.444 ms | 54.597 ms | 28.073 ms | 19.320 ms | 19.378 ms | — | — | 4.462 ms | 1.635 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | — | — | — | — | 440.586 ms | 230.931 ms | 165.412 ms | 165.836 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 817.503 μs | 417.490 μs | 213.933 μs | 113.394 μs | 917.758 μs | 450.694 μs | 233.102 μs | 121.241 μs | — | — | 964.417 μs | 88.221 μs |
| inverse_laplacian! scalar | Float32 128^3 | — | — | — | — | 3.893 ms | 1.324 ms | 667.087 μs | 349.114 μs | — | — | — | 79.900 μs |
| inverse_laplacian! scalar | Float32 256^3 | — | — | — | — | 31.326 ms | 10.539 ms | 5.342 ms | 2.790 ms | — | — | — | 283.933 μs |
| inverse_laplacian! scalar | Float32 512^3 | — | — | — | — | 250.032 ms | 84.129 ms | 43.414 ms | 27.550 ms | — | — | — | — |
| inverse_laplacian! scalar | Float32 64^3 | — | — | — | — | 495.954 μs | 177.332 μs | 92.981 μs | 52.350 μs | — | — | — | 59.361 μs |
| inverse_laplacian! scalar | Float64 128^3 | — | — | — | — | 4.253 ms | 1.428 ms | 720.688 μs | 370.144 μs | — | — | — | 98.061 μs |
| inverse_laplacian! scalar | Float64 256^3 | — | — | — | — | 34.362 ms | 11.547 ms | 5.807 ms | 4.837 ms | — | — | — | 411.984 μs |
| inverse_laplacian! scalar | Float64 512^3 | — | — | — | — | 273.643 ms | 91.587 ms | 54.836 ms | 55.058 ms | — | — | — | — |
| inverse_laplacian! scalar | Float64 64^3 | — | — | — | — | 541.515 μs | 190.532 μs | 99.711 μs | 55.850 μs | — | — | — | 61.690 μs |
| laplacian! scalar | Float32 128^3 | 2.064 ms | 654.294 μs | 335.668 μs | 174.654 μs | 2.143 ms | 491.695 μs | 249.313 μs | 129.981 μs | 265.103 μs | 1.910 ms | 1.181 ms | 69.090 μs |
| laplacian! scalar | Float32 256^3 | 17.204 ms | 6.266 ms | 5.114 ms | 4.573 ms | 16.995 ms | 3.872 ms | 1.943 ms | 1.185 ms | — | 5.490 ms | 1.688 ms | 246.752 μs |
| laplacian! scalar | Float32 512^3 | — | — | — | — | 136.428 ms | 30.777 ms | 25.906 ms | 26.314 ms | — | — | 5.262 ms | — |
| laplacian! scalar | Float32 64^3 | 253.409 μs | 90.201 μs | 49.778 μs | 29.951 μs | 274.603 μs | 68.540 μs | 36.421 μs | 22.180 μs | 83.431 μs | 1.563 ms | 957.239 μs | 59.830 μs |
| laplacian! scalar | Float64 128^3 | 2.151 ms | 818.689 μs | 625.527 μs | 453.410 μs | 2.211 ms | 527.715 μs | 267.433 μs | 139.722 μs | 278.082 μs | 1.957 ms | 1.174 ms | 75.841 μs |
| laplacian! scalar | Float64 256^3 | 17.670 ms | 12.629 ms | 11.985 ms | 11.511 ms | 17.767 ms | 5.144 ms | 4.726 ms | 4.823 ms | — | 4.740 ms | 1.795 ms | 409.704 μs |
| laplacian! scalar | Float64 512^3 | — | — | — | — | 141.764 ms | 53.880 ms | 54.053 ms | 55.002 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 258.431 μs | 94.484 μs | 52.006 μs | 32.627 μs | 282.493 μs | 73.111 μs | 39.311 μs | 23.510 μs | 84.420 μs | 1.586 ms | 1.058 ms | 66.070 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.568 ms | 6.270 ms | 4.679 ms | 4.632 ms | 9.651 ms | 4.893 ms | 2.447 ms | 1.236 ms | — | — | 1.173 ms | 224.202 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 95.270 ms | 51.396 ms | 45.242 ms | 43.393 ms | 78.701 ms | 42.717 ms | 25.140 ms | 24.248 ms | — | — | 2.615 ms | 1.208 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | — | — | — | — | 653.193 ms | 327.203 ms | 209.125 ms | 200.883 ms | — | — | 14.783 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.541 ms | 759.204 μs | 384.861 μs | 200.176 μs | 1.222 ms | 618.766 μs | 309.944 μs | 158.772 μs | — | — | 1.040 ms | 68.601 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 14.266 ms | 11.445 ms | 10.440 ms | 10.391 ms | 10.722 ms | 5.746 ms | 3.769 ms | 3.755 ms | — | — | 1.627 ms | 360.573 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 116.759 ms | 95.790 ms | 88.096 ms | 86.966 ms | 85.278 ms | 54.408 ms | 49.125 ms | 49.585 ms | — | — | 4.370 ms | 2.309 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | — | — | — | — | 702.874 ms | 427.791 ms | 393.922 ms | 399.066 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.606 ms | 785.084 μs | 414.935 μs | 219.733 μs | 1.274 ms | 646.057 μs | 325.753 μs | 167.081 μs | — | — | 1.192 ms | 93.121 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.848 ms | 519.172 μs | 460.198 μs | 358.481 μs | 1.165 μs | 1.162 μs | 1.164 μs | 1.164 μs | 296.642 μs | 1.855 ms | 991.293 μs | 88.851 μs |
| assignment_window | Float32 256^3 | 27.534 ms | 4.133 ms | 5.588 ms | 3.470 ms | 2.229 μs | 2.225 μs | 2.234 μs | 2.239 μs | — | 3.952 ms | 1.684 ms | 90.071 μs |
| assignment_window | Float32 512^3 | — | — | — | — | 4.474 μs | 4.457 μs | 4.466 μs | 4.463 μs | — | — | 5.043 ms | — |
| assignment_window | Float32 64^3 | 240.424 μs | 65.194 μs | 44.367 μs | 38.678 μs | 607.108 ns | 612.284 ns | 608.691 ns | 607.263 ns | 138.651 μs | 1.640 ms | 1.027 ms | 88.681 μs |
| assignment_window | Float64 128^3 | 1.901 ms | 1.011 ms | 820.985 μs | 575.925 μs | 1.549 μs | 1.562 μs | 1.559 μs | 1.555 μs | 306.863 μs | 1.901 ms | 1.136 ms | 98.751 μs |
| assignment_window | Float64 256^3 | 41.039 ms | 8.489 ms | 9.793 ms | 6.226 ms | 3.107 μs | 3.086 μs | 3.066 μs | 3.103 μs | — | 4.237 ms | 1.784 ms | 98.291 μs |
| assignment_window | Float64 512^3 | — | — | — | — | 5.974 μs | 5.972 μs | 6.016 μs | 5.976 μs | — | — | — | — |
| assignment_window | Float64 64^3 | 237.586 μs | 68.329 μs | 65.607 μs | 64.938 μs | 820.000 ns | 822.125 ns | 819.747 ns | 821.500 ns | 141.232 μs | 1.542 ms | 1.162 ms | 92.741 μs |
| combine!∘kernel vector | Float32 128^3 | 4.099 ms | 2.240 ms | 1.715 ms | 1.645 ms | 3.153 ms | 1.553 ms | 780.349 μs | 396.685 μs | — | — | 957.518 μs | 137.302 μs |
| combine!∘kernel vector | Float32 256^3 | 37.490 ms | 22.146 ms | 20.259 ms | 19.790 ms | 27.071 ms | 14.815 ms | 9.942 ms | 9.920 ms | — | — | 1.958 ms | 915.869 μs |
| combine!∘kernel vector | Float32 512^3 | — | — | — | — | 242.188 ms | 137.256 ms | 92.844 ms | 93.500 ms | — | — | 8.534 ms | — |
| combine!∘kernel vector | Float32 64^3 | 494.715 μs | 267.940 μs | 134.409 μs | 75.209 μs | 418.054 μs | 206.482 μs | 104.311 μs | 55.291 μs | — | — | 1.101 ms | 65.640 μs |
| combine!∘kernel vector | Float64 128^3 | 5.648 ms | 4.900 ms | 4.435 ms | 4.427 ms | 3.750 ms | 2.073 ms | 1.087 ms | 733.548 μs | — | — | 1.469 ms | 290.733 μs |
| combine!∘kernel vector | Float64 256^3 | 50.199 ms | 44.417 ms | 40.732 ms | 40.012 ms | 34.135 ms | 23.054 ms | 21.910 ms | 23.355 ms | — | — | 3.008 ms | 1.785 ms |
| combine!∘kernel vector | Float64 512^3 | — | — | — | — | 262.249 ms | 188.005 ms | 183.838 ms | 184.548 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 516.288 μs | 283.545 μs | 142.485 μs | 81.472 μs | 383.513 μs | 233.493 μs | 114.541 μs | 64.600 μs | — | — | 1.001 ms | 81.561 μs |
| convolve! scalar | Float32 128^3 | 1.622 ms | 314.111 μs | 205.492 μs | 87.696 μs | 912.118 μs | 105.091 μs | 54.280 μs | 37.070 μs | 220.032 μs | 1.755 ms | 877.910 μs | 70.201 μs |
| convolve! scalar | Float32 256^3 | 13.663 ms | 8.198 ms | 7.751 ms | 7.123 ms | 7.561 ms | 2.901 ms | 2.660 ms | 2.733 ms | — | 3.659 ms | 1.656 ms | 312.084 μs |
| convolve! scalar | Float32 512^3 | — | — | — | — | 61.401 ms | 37.024 ms | 36.517 ms | 37.050 ms | — | — | 4.192 ms | — |
| convolve! scalar | Float32 64^3 | 202.015 μs | 26.689 μs | 14.629 μs | 11.683 μs | 116.681 μs | 16.630 μs | 8.980 μs | 7.377 μs | 78.951 μs | 1.480 ms | 1.035 ms | 48.690 μs |
| convolve! scalar | Float64 128^3 | 1.847 ms | 1.390 ms | 1.185 ms | 1.117 ms | 1.003 ms | 171.322 μs | 90.711 μs | 72.411 μs | 302.553 μs | 1.784 ms | 1.135 ms | 84.271 μs |
| convolve! scalar | Float64 256^3 | 19.136 ms | 16.911 ms | 16.014 ms | 15.178 ms | 10.896 ms | 7.875 ms | 7.614 ms | 7.752 ms | — | 4.442 ms | 2.019 ms | 565.926 μs |
| convolve! scalar | Float64 512^3 | — | — | — | — | 90.022 ms | 73.498 ms | 73.710 ms | 74.113 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 181.121 μs | 55.189 μs | 26.100 μs | 18.116 μs | 128.772 μs | 24.761 μs | 13.880 μs | 10.500 μs | 78.591 μs | 1.618 ms | 951.395 μs | 52.080 μs |
| convolve! vector | Float32 128^3 | 2.765 ms | 1.925 ms | 1.659 ms | 1.593 ms | 2.104 ms | 1.097 ms | 553.146 μs | 294.883 μs | 731.727 μs | 2.557 ms | 921.484 μs | 110.401 μs |
| convolve! vector | Float32 256^3 | 26.736 ms | 21.677 ms | 20.002 ms | 19.668 ms | 20.036 ms | 11.039 ms | 9.833 ms | 9.898 ms | — | 10.821 ms | 1.185 ms | 676.457 μs |
| convolve! vector | Float32 512^3 | — | — | — | — | 177.559 ms | 94.689 ms | 92.337 ms | 93.004 ms | — | — | 6.065 ms | — |
| convolve! vector | Float32 64^3 | 318.386 μs | 178.979 μs | 90.308 μs | 49.964 μs | 269.893 μs | 147.731 μs | 73.570 μs | 40.400 μs | 161.751 μs | 1.595 ms | 1.094 ms | 56.191 μs |
| convolve! vector | Float64 128^3 | 5.261 ms | 4.843 ms | 4.388 ms | 4.243 ms | 2.604 ms | 1.543 ms | 868.070 μs | 738.649 μs | 792.657 μs | 2.910 ms | 1.329 ms | 219.422 μs |
| convolve! vector | Float64 256^3 | 46.440 ms | 43.366 ms | 40.450 ms | 39.756 ms | 30.481 ms | 22.783 ms | 21.906 ms | 23.329 ms | — | 12.297 ms | 2.365 ms | 1.290 ms |
| convolve! vector | Float64 512^3 | — | — | — | — | 227.886 ms | 186.909 ms | 183.846 ms | 184.781 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 284.305 μs | 169.910 μs | 89.571 μs | 54.907 μs | 219.542 μs | 137.861 μs | 72.331 μs | 41.451 μs | 167.451 μs | 1.655 ms | 1.102 ms | 71.831 μs |
| convolve! vector ∘ radial    | Float32 128^3 | — | — | — | — | 2.493 ms | 1.263 ms | 628.966 μs | 324.564 μs | — | — | — | 133.482 μs |
| convolve! vector ∘ radial    | Float32 256^3 | — | — | — | — | 23.577 ms | 13.222 ms | 10.027 ms | 10.891 ms | — | — | — | 678.597 μs |
| convolve! vector ∘ radial    | Float32 512^3 | — | — | — | — | 187.229 ms | 103.641 ms | 89.840 ms | 82.475 ms | — | — | — | — |
| convolve! vector ∘ radial    | Float32 64^3 | — | — | — | — | 314.512 μs | 159.812 μs | 82.211 μs | 43.751 μs | — | — | — | 62.031 μs |
| convolve! vector ∘ radial    | Float64 128^3 | — | — | — | — | 2.877 ms | 1.452 ms | 727.018 μs | 404.765 μs | — | — | — | 187.602 μs |
| convolve! vector ∘ radial    | Float64 256^3 | — | — | — | — | 23.880 ms | 18.494 ms | 18.713 ms | 19.084 ms | — | — | — | 1.115 ms |
| convolve! vector ∘ radial    | Float64 512^3 | — | — | — | — | 193.195 ms | 156.538 ms | 162.630 ms | 163.992 ms | — | — | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | — | — | — | — | 354.303 μs | 176.221 μs | 92.101 μs | 49.101 μs | — | — | — | 67.431 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | — | — | — | — | 2.099 ms | 1.102 ms | 550.776 μs | 295.813 μs | — | — | — | 107.911 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | — | — | — | — | 20.075 ms | 11.009 ms | 9.814 ms | 9.860 ms | — | — | — | 673.947 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | — | — | — | — | 176.788 ms | 94.795 ms | 92.314 ms | 92.567 ms | — | — | — | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | — | — | — | — | 269.992 μs | 147.032 μs | 73.701 μs | 40.521 μs | — | — | — | 59.460 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | — | — | — | — | 2.610 ms | 1.545 ms | 875.610 μs | 745.458 μs | — | — | — | 222.422 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | — | — | — | — | 30.312 ms | 22.468 ms | 21.886 ms | 22.004 ms | — | — | — | 1.294 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | — | — | — | — | 224.118 ms | 184.952 ms | 183.724 ms | 184.011 ms | — | — | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | — | — | — | — | 220.392 μs | 136.321 μs | 72.571 μs | 41.180 μs | — | — | — | 75.411 μs |
| convolve! vector ∘ separable | Float32 128^3 | — | — | — | — | 4.691 ms | 2.348 ms | 1.177 ms | 591.737 μs | — | — | — | 137.751 μs |
| convolve! vector ∘ separable | Float32 256^3 | — | — | — | — | 37.219 ms | 18.666 ms | 9.370 ms | 8.408 ms | — | — | — | 681.427 μs |
| convolve! vector ∘ separable | Float32 512^3 | — | — | — | — | 296.344 ms | 148.459 ms | 82.561 ms | 82.864 ms | — | — | — | — |
| convolve! vector ∘ separable | Float32 64^3 | — | — | — | — | 588.495 μs | 297.703 μs | 151.442 μs | 77.821 μs | — | — | — | 61.111 μs |
| convolve! vector ∘ separable | Float64 128^3 | — | — | — | — | 3.953 ms | 1.987 ms | 1.000 ms | 512.766 μs | — | — | — | 269.583 μs |
| convolve! vector ∘ separable | Float64 256^3 | — | — | — | — | 33.636 ms | 19.124 ms | 18.925 ms | 19.238 ms | — | — | — | 1.666 ms |
| convolve! vector ∘ separable | Float64 512^3 | — | — | — | — | 264.922 ms | 160.595 ms | 163.723 ms | 164.062 ms | — | — | — | — |
| convolve! vector ∘ separable | Float64 64^3 | — | — | — | — | 494.364 μs | 248.733 μs | 126.981 μs | 66.280 μs | — | — | — | 78.711 μs |
| convolve! vector ∘ stored    | Float32 128^3 | — | — | — | — | 2.103 ms | 1.099 ms | 550.906 μs | 294.493 μs | — | — | — | 114.571 μs |
| convolve! vector ∘ stored    | Float32 256^3 | — | — | — | — | 20.176 ms | 11.038 ms | 9.820 ms | 9.889 ms | — | — | — | 687.007 μs |
| convolve! vector ∘ stored    | Float32 512^3 | — | — | — | — | 177.565 ms | 95.079 ms | 92.189 ms | 92.928 ms | — | — | — | — |
| convolve! vector ∘ stored    | Float32 64^3 | — | — | — | — | 271.152 μs | 147.181 μs | 73.471 μs | 40.100 μs | — | — | — | 57.851 μs |
| convolve! vector ∘ stored    | Float64 128^3 | — | — | — | — | 2.627 ms | 1.551 ms | 884.070 μs | 739.568 μs | — | — | — | 214.052 μs |
| convolve! vector ∘ stored    | Float64 256^3 | — | — | — | — | 30.495 ms | 22.771 ms | 21.893 ms | 22.076 ms | — | — | — | 1.296 ms |
| convolve! vector ∘ stored    | Float64 512^3 | — | — | — | — | 225.588 ms | 187.844 ms | 184.029 ms | 184.561 ms | — | — | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | — | — | — | — | 219.762 μs | 134.761 μs | 72.521 μs | 41.171 μs | — | — | — | 77.050 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.737 ms | 2.434 ms | 1.659 ms | 900.167 μs | 5.000 ms | 2.126 ms | 1.074 ms | 549.786 μs | — | — | 1.058 ms | 73.931 μs |
| exponential_convolve! scalar | Float32 256^3 | 34.376 ms | 13.310 ms | 7.294 ms | 5.716 ms | 39.675 ms | 16.597 ms | 8.299 ms | 4.215 ms | — | — | 1.651 ms | 246.262 μs |
| exponential_convolve! scalar | Float32 512^3 | — | — | — | — | 316.995 ms | 132.278 ms | 67.827 ms | 35.434 ms | — | — | 5.951 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 2.197 ms | 1.065 ms | 569.902 μs | 299.039 μs | 642.486 μs | 280.343 μs | 144.952 μs | 78.671 μs | — | — | 999.111 μs | 57.381 μs |
| exponential_convolve! scalar | Float64 128^3 | 8.249 ms | 3.745 ms | 2.332 ms | 1.452 ms | 5.565 ms | 2.405 ms | 1.195 ms | 608.087 μs | — | — | 1.328 ms | 123.821 μs |
| exponential_convolve! scalar | Float64 256^3 | 55.341 ms | 24.571 ms | 14.316 ms | 11.623 ms | 44.049 ms | 18.862 ms | 9.447 ms | 4.989 ms | — | — | 2.622 ms | 626.137 μs |
| exponential_convolve! scalar | Float64 512^3 | — | — | — | — | 350.652 ms | 149.322 ms | 74.958 ms | 55.011 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 728.857 μs | 327.894 μs | 171.385 μs | 96.734 μs | 695.806 μs | 307.533 μs | 157.852 μs | 85.961 μs | — | — | 986.434 μs | 69.091 μs |
| exponential_convolve! vector | Float32 128^3 | 19.222 ms | 9.091 ms | 5.798 ms | 3.138 ms | 16.463 ms | 7.697 ms | 3.855 ms | 1.951 ms | — | — | 1.208 ms | 140.221 μs |
| exponential_convolve! vector | Float32 256^3 | 116.910 ms | 53.126 ms | 28.672 ms | 18.878 ms | 130.546 ms | 60.463 ms | 31.173 ms | 15.407 ms | — | — | 3.202 ms | 697.327 μs |
| exponential_convolve! vector | Float32 512^3 | — | — | — | — | 1.040 s | 480.920 ms | 245.605 ms | 128.695 ms | — | — | 14.658 ms | — |
| exponential_convolve! vector | Float32 64^3 | 6.916 ms | 3.524 ms | 1.824 ms | 944.164 μs | 2.111 ms | 998.830 μs | 502.085 μs | 259.602 μs | — | — | 1.051 ms | 61.500 μs |
| exponential_convolve! vector | Float64 128^3 | 27.270 ms | 12.988 ms | 7.841 ms | 5.008 ms | 18.543 ms | 8.657 ms | 4.333 ms | 2.214 ms | — | — | 1.842 ms | 279.013 μs |
| exponential_convolve! vector | Float64 256^3 | 184.797 ms | 87.239 ms | 47.961 ms | 35.237 ms | 146.215 ms | 68.202 ms | 34.194 ms | 19.414 ms | — | — | 5.713 ms | 1.741 ms |
| exponential_convolve! vector | Float64 512^3 | — | — | — | — | 1.163 s | 542.387 ms | 278.508 ms | 165.669 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.524 ms | 1.171 ms | 604.600 μs | 321.396 μs | 2.328 ms | 1.094 ms | 552.736 μs | 282.993 μs | — | — | 1.060 ms | 83.511 μs |
| inv separable | Float32 128^3 | — | — | — | — | 764.074 ns | 762.046 ns | 762.139 ns | 766.149 ns | — | — | — | 151.631 μs |
| inv separable | Float32 256^3 | — | — | — | — | 1.571 μs | 1.561 μs | 1.555 μs | 1.560 μs | — | — | — | 145.891 μs |
| inv separable | Float32 512^3 | — | — | — | — | 3.033 μs | 3.021 μs | 3.025 μs | 3.039 μs | — | — | — | — |
| inv separable | Float32 64^3 | — | — | — | — | 408.555 ns | 414.755 ns | 408.005 ns | 412.800 ns | — | — | — | 148.501 μs |
| inv separable | Float64 128^3 | — | — | — | — | 1.061 μs | 1.082 μs | 1.057 μs | 1.072 μs | — | — | — | 149.961 μs |
| inv separable | Float64 256^3 | — | — | — | — | 2.062 μs | 2.036 μs | 2.039 μs | 2.041 μs | — | — | — | 155.332 μs |
| inv separable | Float64 512^3 | — | — | — | — | 3.930 μs | 3.980 μs | 3.983 μs | 3.959 μs | — | — | — | — |
| inv separable | Float64 64^3 | — | — | — | — | 521.672 ns | 523.876 ns | 521.262 ns | 535.346 ns | — | — | — | 138.551 μs |
| materialize_kernel radial | Float32 128^3 | — | — | — | — | 1.131 ms | 351.704 μs | 178.062 μs | 92.901 μs | — | — | — | 82.600 μs |
| materialize_kernel radial | Float32 256^3 | — | — | — | — | 8.926 ms | 2.767 ms | 2.015 ms | 1.537 ms | — | — | — | 222.092 μs |
| materialize_kernel radial | Float32 512^3 | — | — | — | — | 71.013 ms | 22.141 ms | 17.410 ms | 17.141 ms | — | — | — | — |
| materialize_kernel radial | Float32 64^3 | — | — | — | — | 145.731 μs | 47.990 μs | 25.540 μs | 15.660 μs | — | — | — | 64.961 μs |
| materialize_kernel radial | Float64 128^3 | — | — | — | — | 1.174 ms | 376.994 μs | 288.473 μs | 229.313 μs | — | — | — | 94.421 μs |
| materialize_kernel radial | Float64 256^3 | — | — | — | — | 9.383 ms | 3.912 ms | 3.883 ms | 3.884 ms | — | — | — | 238.052 μs |
| materialize_kernel radial | Float64 512^3 | — | — | — | — | 75.103 ms | 92.578 ms | 53.050 ms | 35.733 ms | — | — | — | — |
| materialize_kernel radial | Float64 64^3 | — | — | — | — | 151.132 μs | 48.161 μs | 25.950 μs | 15.840 μs | — | — | — | 83.720 μs |
| materialize_kernel separable | Float32 128^3 | — | — | — | — | 1.535 ms | 446.394 μs | 225.902 μs | 116.831 μs | — | — | — | 80.341 μs |
| materialize_kernel separable | Float32 256^3 | — | — | — | — | 12.161 ms | 3.499 ms | 1.931 ms | 1.724 ms | — | — | — | 226.492 μs |
| materialize_kernel separable | Float32 512^3 | — | — | — | — | 97.176 ms | 28.049 ms | 18.842 ms | 17.767 ms | — | — | — | — |
| materialize_kernel separable | Float32 64^3 | — | — | — | — | 196.452 μs | 59.991 μs | 31.761 μs | 18.800 μs | — | — | — | 61.971 μs |
| materialize_kernel separable | Float64 128^3 | — | — | — | — | 1.450 ms | 457.755 μs | 257.603 μs | 266.963 μs | — | — | — | 108.401 μs |
| materialize_kernel separable | Float64 256^3 | — | — | — | — | 11.484 ms | 4.262 ms | 4.064 ms | 3.867 ms | — | — | — | 414.394 μs |
| materialize_kernel separable | Float64 512^3 | — | — | — | — | 92.257 ms | 104.552 ms | 62.440 ms | 44.154 ms | — | — | — | — |
| materialize_kernel separable | Float64 64^3 | — | — | — | — | 186.652 μs | 61.341 μs | 32.540 μs | 19.260 μs | — | — | — | 71.631 μs |
| radial_kernel | Float32 128^3 | — | — | — | — | 3.200 ns | 3.050 ns | 3.200 ns | 3.050 ns | — | — | — | 1.676 μs |
| radial_kernel | Float32 256^3 | — | — | — | — | 3.210 ns | 3.050 ns | 3.200 ns | 3.050 ns | — | — | — | 1.264 μs |
| radial_kernel | Float32 512^3 | — | — | — | — | 3.210 ns | 3.050 ns | 3.210 ns | 3.050 ns | — | — | — | — |
| radial_kernel | Float32 64^3 | — | — | — | — | 3.200 ns | 3.050 ns | 3.200 ns | 3.050 ns | — | — | — | 1.569 μs |
| radial_kernel | Float64 128^3 | — | — | — | — | 3.190 ns | 3.160 ns | 3.170 ns | 3.180 ns | — | — | — | 1.592 μs |
| radial_kernel | Float64 256^3 | — | — | — | — | 3.200 ns | 3.190 ns | 3.170 ns | 3.180 ns | — | — | — | 1.149 μs |
| radial_kernel | Float64 512^3 | — | — | — | — | 3.200 ns | 3.170 ns | 3.180 ns | 3.180 ns | — | — | — | — |
| radial_kernel | Float64 64^3 | — | — | — | — | 3.190 ns | 3.170 ns | 3.180 ns | 3.190 ns | — | — | — | 1.200 μs |
| spectral_band | Float32 128^3 | 4.252 ms | 1.621 ms | 834.592 μs | 441.121 μs | 10.450 ns | 9.009 ns | 9.760 ns | 9.149 ns | 334.154 μs | 2.050 ms | 1.005 ms | 1.548 μs |
| spectral_band | Float32 256^3 | 46.117 ms | 12.797 ms | 10.084 ms | 5.548 ms | 10.460 ns | 9.029 ns | 9.760 ns | 9.169 ns | — | 6.344 ms | 1.755 ms | 1.577 μs |
| spectral_band | Float32 512^3 | — | — | — | — | 10.460 ns | 9.029 ns | 9.770 ns | 9.169 ns | — | — | 7.315 ms | — |
| spectral_band | Float32 64^3 | 540.920 μs | 216.585 μs | 115.386 μs | 63.530 μs | 10.460 ns | 9.029 ns | 9.770 ns | 9.179 ns | 106.071 μs | 1.537 ms | 1.000 ms | 1.344 μs |
| spectral_band | Float64 128^3 | 4.310 ms | 1.590 ms | 966.909 μs | 624.952 μs | 10.080 ns | 9.780 ns | 10.211 ns | 10.541 ns | 361.113 μs | 2.105 ms | 1.221 ms | 1.668 μs |
| spectral_band | Float64 256^3 | 58.860 ms | 12.495 ms | 13.852 ms | 8.086 ms | 10.090 ns | 9.830 ns | 10.310 ns | 10.591 ns | — | 5.611 ms | 2.014 ms | 1.307 μs |
| spectral_band | Float64 512^3 | — | — | — | — | 10.100 ns | 9.820 ns | 10.310 ns | 10.601 ns | — | — | — | — |
| spectral_band | Float64 64^3 | 530.525 μs | 214.887 μs | 113.729 μs | 71.733 μs | 10.100 ns | 9.810 ns | 10.320 ns | 10.582 ns | 110.411 μs | 1.651 ms | 866.015 μs | 1.548 μs |
| spectral_cutoff | Float32 128^3 | 4.270 ms | 1.655 ms | 839.296 μs | 442.373 μs | 9.910 ns | 9.740 ns | 10.521 ns | 9.459 ns | 331.623 μs | 2.046 ms | 1.093 ms | 1.772 μs |
| spectral_cutoff | Float32 256^3 | 45.919 ms | 12.710 ms | 10.131 ms | 5.435 ms | 9.890 ns | 9.720 ns | 10.521 ns | 9.449 ns | — | 5.403 ms | 1.983 ms | 1.312 μs |
| spectral_cutoff | Float32 512^3 | — | — | — | — | 9.930 ns | 9.710 ns | 10.541 ns | 9.449 ns | — | — | 6.140 ms | — |
| spectral_cutoff | Float32 64^3 | 548.228 μs | 217.012 μs | 114.396 μs | 63.484 μs | 9.930 ns | 9.730 ns | 10.521 ns | 9.439 ns | 108.881 μs | 1.625 ms | 1.105 ms | 1.313 μs |
| spectral_cutoff | Float64 128^3 | 4.261 ms | 1.590 ms | 972.055 μs | 631.094 μs | 11.562 ns | 9.910 ns | 10.280 ns | 10.771 ns | 351.793 μs | 2.120 ms | 1.131 ms | 1.319 μs |
| spectral_cutoff | Float64 256^3 | 59.017 ms | 12.879 ms | 13.948 ms | 8.048 ms | 11.552 ns | 9.950 ns | 10.290 ns | 10.721 ns | — | 5.621 ms | 2.006 ms | 1.580 μs |
| spectral_cutoff | Float64 512^3 | — | — | — | — | 11.572 ns | 9.880 ns | 10.270 ns | 10.701 ns | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 534.876 μs | 213.217 μs | 114.093 μs | 69.801 μs | 11.592 ns | 9.940 ns | 10.310 ns | 10.741 ns | 117.711 μs | 1.647 ms | 1.006 ms | 1.498 μs |
| squared_wavenumber_field | Float32 128^3 | 1.881 ms | 489.911 μs | 448.601 μs | 349.437 μs | 1.374 ms | 297.403 μs | 151.111 μs | 78.590 μs | 262.463 μs | 1.824 ms | 961.813 μs | 92.101 μs |
| squared_wavenumber_field | Float32 256^3 | 27.592 ms | 4.127 ms | 5.585 ms | 3.472 ms | 10.855 ms | 2.331 ms | 1.572 ms | 1.806 ms | — | 3.812 ms | 1.541 ms | 218.812 μs |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | 86.601 ms | 21.347 ms | 18.293 ms | 17.899 ms | — | — | 4.991 ms | — |
| squared_wavenumber_field | Float32 64^3 | 233.436 μs | 63.047 μs | 35.087 μs | 39.058 μs | 176.412 μs | 41.971 μs | 22.720 μs | 14.111 μs | 91.321 μs | 1.517 ms | 954.784 μs | 61.420 μs |
| squared_wavenumber_field | Float64 128^3 | 1.904 ms | 1.001 ms | 818.893 μs | 591.955 μs | 1.418 ms | 405.184 μs | 287.723 μs | 269.653 μs | 264.163 μs | 1.805 ms | 1.079 ms | 94.901 μs |
| squared_wavenumber_field | Float64 256^3 | 41.025 ms | 8.109 ms | 9.821 ms | 6.080 ms | 11.254 ms | 4.346 ms | 4.294 ms | 4.072 ms | — | 4.151 ms | 1.758 ms | 249.233 μs |
| squared_wavenumber_field | Float64 512^3 | — | — | — | — | 89.939 ms | 91.026 ms | 57.477 ms | 43.486 ms | — | — | — | — |
| squared_wavenumber_field | Float64 64^3 | 235.679 μs | 63.357 μs | 67.986 μs | 62.943 μs | 182.211 μs | 42.880 μs | 22.770 μs | 14.330 μs | 88.931 μs | 1.612 ms | 1.059 ms | 68.861 μs |
| translation_kernel | Float32 128^3 | 1.839 ms | 787.619 μs | 481.587 μs | 331.665 μs | 1.406 μs | 1.416 μs | 1.416 μs | 1.416 μs | — | — | 1.218 ms | 76.210 μs |
| translation_kernel | Float32 256^3 | 27.554 ms | 6.188 ms | 6.949 ms | 4.066 ms | 2.741 μs | 2.734 μs | 2.744 μs | 2.724 μs | — | — | 1.653 ms | 78.820 μs |
| translation_kernel | Float32 512^3 | — | — | — | — | 5.307 μs | 5.295 μs | 5.338 μs | 5.305 μs | — | — | 5.084 ms | — |
| translation_kernel | Float32 64^3 | 232.583 μs | 105.855 μs | 58.738 μs | 40.614 μs | 741.336 ns | 743.287 ns | 742.959 ns | 740.917 ns | — | — | 1.138 ms | 72.321 μs |
| translation_kernel | Float64 128^3 | 1.827 ms | 1.003 ms | 769.033 μs | 536.206 μs | 1.827 μs | 1.825 μs | 1.835 μs | 1.826 μs | — | — | 1.338 ms | 83.781 μs |
| translation_kernel | Float64 256^3 | 41.093 ms | 8.494 ms | 10.708 ms | 6.716 ms | 3.462 μs | 3.479 μs | 3.470 μs | 3.470 μs | — | — | 2.213 ms | 81.141 μs |
| translation_kernel | Float64 512^3 | — | — | — | — | 6.720 μs | 6.730 μs | 6.750 μs | 6.840 μs | — | — | — | — |
| translation_kernel | Float64 64^3 | 231.216 μs | 101.023 μs | 74.401 μs | 60.787 μs | 937.667 ns | 927.190 ns | 929.000 ns | 938.655 ns | — | — | 1.188 ms | 72.971 μs |
| translation_kernel! | Float32 128^3 | — | — | — | — | 1.370 μs | 1.370 μs | 1.371 μs | 1.375 μs | — | — | — | 61.521 μs |
| translation_kernel! | Float32 256^3 | — | — | — | — | 2.626 μs | 2.621 μs | 2.621 μs | 2.624 μs | — | — | — | 59.050 μs |
| translation_kernel! | Float32 512^3 | — | — | — | — | 5.113 μs | 5.122 μs | 5.120 μs | 5.188 μs | — | — | — | — |
| translation_kernel! | Float32 64^3 | — | — | — | — | 699.103 ns | 707.438 ns | 703.965 ns | 698.688 ns | — | — | — | 57.261 μs |
| translation_kernel! | Float64 128^3 | — | — | — | — | 1.691 μs | 1.684 μs | 1.695 μs | 1.688 μs | — | — | — | 62.911 μs |
| translation_kernel! | Float64 256^3 | — | — | — | — | 3.246 μs | 3.244 μs | 3.248 μs | 3.240 μs | — | — | — | 71.110 μs |
| translation_kernel! | Float64 512^3 | — | — | — | — | 6.408 μs | 6.350 μs | 6.362 μs | 6.412 μs | — | — | — | — |
| translation_kernel! | Float64 64^3 | — | — | — | — | 875.741 ns | 877.426 ns | 878.679 ns | 875.472 ns | — | — | — | 60.130 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 28.888 ms | 13.922 ms | 7.765 ms | 4.633 ms | 20.862 ms | 11.014 ms | 5.934 ms | 3.416 ms | 2.280 ms | 4.864 ms | 1.343 ms | 206.342 μs |
| anterpolate! CatmullRom | Float32 256^3 | 436.132 ms | 225.143 ms | 120.356 ms | 75.195 ms | 174.573 ms | 88.430 ms | 45.314 ms | 23.806 ms | — | 17.932 ms | 4.044 ms | 2.904 ms |
| anterpolate! CatmullRom | Float32 512^3 | — | — | — | — | 2.957 s | 1.507 s | 777.939 ms | 436.716 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.238 ms | 1.913 ms | 1.248 ms | 938.078 μs | 2.523 ms | 1.450 ms | 931.189 μs | 653.626 μs | 116.972 μs | 2.057 ms | 1.220 ms | 105.631 μs |
| anterpolate! CatmullRom | Float64 128^3 | 34.657 ms | 16.258 ms | 8.125 ms | 4.852 ms | 22.096 ms | 11.481 ms | 6.131 ms | 3.566 ms | 2.691 ms | 4.862 ms | 1.628 ms | 226.222 μs |
| anterpolate! CatmullRom | Float64 256^3 | 546.414 ms | 287.805 ms | 165.743 ms | 114.407 ms | 261.355 ms | 131.553 ms | 69.933 ms | 35.914 ms | — | 19.810 ms | 4.795 ms | 4.684 ms |
| anterpolate! CatmullRom | Float64 512^3 | — | — | — | — | 3.227 s | 1.746 s | 924.191 ms | 526.949 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.389 ms | 1.879 ms | 1.262 ms | 943.395 μs | 2.529 ms | 1.496 ms | 983.019 μs | 697.637 μs | 185.312 μs | 2.004 ms | 1.201 ms | 117.171 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 206.898 ms | 102.438 ms | 54.108 ms | 29.977 ms | 159.955 ms | 80.400 ms | 40.668 ms | 21.769 ms | 12.241 ms | 15.478 ms | 4.182 ms | 1.005 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.398 s | 1.309 s | 748.243 ms | 530.262 ms | 1.287 s | 643.069 ms | 322.902 ms | 164.759 ms | — | 48.567 ms | 18.203 ms | 15.001 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 11.781 s | 5.953 s | 3.028 s | 1.640 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.505 ms | 13.324 ms | 8.405 ms | 5.731 ms | 19.873 ms | 10.606 ms | 6.455 ms | 4.342 ms | 486.825 μs | 5.959 ms | 2.191 ms | 339.203 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 229.887 ms | 111.011 ms | 56.260 ms | 31.446 ms | 160.534 ms | 80.788 ms | 40.634 ms | 21.639 ms | 13.808 ms | 16.564 ms | 4.883 ms | 1.163 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.816 s | 1.516 s | 925.966 ms | 682.498 ms | 1.399 s | 698.880 ms | 360.273 ms | 177.875 ms | — | 66.043 ms | 28.833 ms | 24.262 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 12.551 s | 6.555 s | 3.412 s | 2.224 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 25.148 ms | 13.373 ms | 8.536 ms | 5.942 ms | 19.972 ms | 10.734 ms | 6.563 ms | 4.432 ms | 825.268 μs | 5.503 ms | 2.720 ms | 331.223 μs |
| anterpolate! NUFFT | Float32 128^3 | 440.339 ms | 240.566 ms | 162.121 ms | 126.581 ms | 358.491 ms | 185.715 ms | 93.012 ms | 61.987 ms | 20.177 ms | 18.762 ms | 5.604 ms | 2.775 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.637 s | 2.564 s | 1.595 s | 1.215 s | 3.704 s | 1.925 s | 1.040 s | 677.920 ms | — | 120.799 ms | 32.967 ms | 28.611 ms |
| anterpolate! NUFFT | Float32 512^3 | — | — | — | — | 31.164 s | 16.426 s | 9.065 s | 5.512 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 33.293 ms | 18.266 ms | 11.751 ms | 8.822 ms | 27.265 ms | 14.387 ms | 8.685 ms | 5.893 ms | 1.989 ms | 6.296 ms | 2.380 ms | 454.035 μs |
| anterpolate! NUFFT | Float64 128^3 | 581.682 ms | 329.204 ms | 231.408 ms | 191.318 ms | 426.499 ms | 224.606 ms | 128.234 ms | 104.187 ms | 30.358 ms | 22.503 ms | 10.016 ms | 6.558 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.457 s | 3.104 s | 2.052 s | 1.678 s | 3.650 s | 2.041 s | 1.237 s | 891.669 ms | — | 160.735 ms | 70.065 ms | 58.706 ms |
| anterpolate! NUFFT | Float64 512^3 | — | — | — | — | 40.349 s | 21.839 s | 12.741 s | 8.293 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 40.161 ms | 22.518 ms | 15.032 ms | 11.464 ms | 33.409 ms | 17.820 ms | 10.928 ms | 7.164 ms | 3.892 ms | 8.203 ms | 3.612 ms | 827.528 μs |
| anterpolate! trilinear | Float32 128^3 | 4.520 ms | 2.277 ms | 1.400 ms | 963.981 μs | 5.158 ms | 2.484 ms | 1.407 ms | 874.330 μs | 460.884 μs | 2.018 ms | 990.949 μs | 81.151 μs |
| anterpolate! trilinear | Float32 256^3 | 89.673 ms | 48.898 ms | 28.408 ms | 21.164 ms | 42.710 ms | 21.996 ms | 11.627 ms | 6.658 ms | — | 6.631 ms | 1.780 ms | 737.858 μs |
| anterpolate! trilinear | Float32 512^3 | — | — | — | — | 747.876 ms | 394.657 ms | 209.540 ms | 119.085 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 491.280 μs | 331.491 μs | 225.859 μs | 179.253 μs | 369.533 μs | 228.742 μs | 173.301 μs | 126.302 μs | 70.080 μs | 1.565 ms | 1.061 ms | 67.541 μs |
| anterpolate! trilinear | Float64 128^3 | 5.640 ms | 2.855 ms | 1.720 ms | 1.321 ms | 6.003 ms | 3.314 ms | 1.900 ms | 1.170 ms | 596.666 μs | 1.980 ms | 1.202 ms | 100.591 μs |
| anterpolate! trilinear | Float64 256^3 | 97.343 ms | 55.716 ms | 36.209 ms | 29.492 ms | 71.728 ms | 36.808 ms | 20.407 ms | 11.337 ms | — | 6.838 ms | 1.761 ms | 1.113 ms |
| anterpolate! trilinear | Float64 512^3 | — | — | — | — | 766.036 ms | 406.167 ms | 225.314 ms | 130.448 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 523.595 μs | 343.748 μs | 259.583 μs | 210.906 μs | 379.254 μs | 238.773 μs | 177.262 μs | 135.031 μs | 83.721 μs | 1.554 ms | 936.908 μs | 77.941 μs |
| interpolate! CatmullRom | Float32 128^3 | 12.564 ms | 6.150 ms | 3.087 ms | 1.711 ms | 5.476 ms | 2.759 ms | 1.410 ms | 745.588 μs | 972.889 μs | 3.140 ms | 1.376 ms | 131.832 μs |
| interpolate! CatmullRom | Float32 256^3 | 298.273 ms | 156.282 ms | 82.104 ms | 53.577 ms | 55.902 ms | 27.950 ms | 14.086 ms | 7.067 ms | — | 14.577 ms | 2.785 ms | 871.938 μs |
| interpolate! CatmullRom | Float32 512^3 | — | — | — | — | 1.862 s | 938.414 ms | 479.812 ms | 267.530 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.333 ms | 715.329 μs | 437.043 μs | 299.843 μs | 613.016 μs | 333.083 μs | 201.572 μs | 136.961 μs | 101.321 μs | 1.724 ms | 1.188 ms | 81.591 μs |
| interpolate! CatmullRom | Float64 128^3 | 17.215 ms | 7.511 ms | 3.790 ms | 1.989 ms | 5.609 ms | 2.854 ms | 1.448 ms | 773.118 μs | 1.411 ms | 2.789 ms | 1.410 ms | 188.222 μs |
| interpolate! CatmullRom | Float64 256^3 | 326.167 ms | 167.984 ms | 98.558 ms | 65.427 ms | 148.820 ms | 74.180 ms | 39.372 ms | 19.260 ms | — | 12.939 ms | 2.854 ms | 1.710 ms |
| interpolate! CatmullRom | Float64 512^3 | — | — | — | — | 1.894 s | 1.058 s | 550.608 ms | 303.054 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.418 ms | 755.274 μs | 460.251 μs | 320.814 μs | 670.306 μs | 355.493 μs | 215.632 μs | 145.281 μs | 166.201 μs | 1.759 ms | 1.283 ms | 110.711 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 77.824 ms | 39.254 ms | 19.789 ms | 10.830 ms | 42.453 ms | 21.228 ms | 10.704 ms | 5.654 ms | 5.370 ms | 14.027 ms | 3.038 ms | 478.225 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.545 s | 885.882 ms | 541.871 ms | 353.399 ms | 374.776 ms | 185.415 ms | 87.678 ms | 43.921 ms | — | 30.216 ms | 11.603 ms | 4.711 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 5.383 s | 2.838 s | 1.505 s | 890.853 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.922 ms | 4.742 ms | 2.891 ms | 1.939 ms | 5.058 ms | 2.686 ms | 1.619 ms | 1.077 ms | 688.416 μs | 3.166 ms | 1.783 ms | 282.133 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 99.290 ms | 48.176 ms | 24.054 ms | 13.184 ms | 41.483 ms | 20.852 ms | 10.490 ms | 5.530 ms | 8.105 ms | 9.517 ms | 2.980 ms | 835.398 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.989 s | 1.100 s | 707.401 ms | 470.630 ms | 582.330 ms | 294.331 ms | 157.109 ms | 75.214 ms | — | 28.103 ms | 10.932 ms | 10.026 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 6.174 s | 3.595 s | 1.938 s | 1.178 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.195 ms | 4.828 ms | 2.989 ms | 2.017 ms | 5.242 ms | 2.765 ms | 1.666 ms | 1.115 ms | 911.428 μs | 3.595 ms | 2.314 ms | 320.863 μs |
| interpolate! NUFFT | Float32 128^3 | 343.312 ms | 196.862 ms | 143.368 ms | 99.919 ms | 241.593 ms | 137.885 ms | 74.001 ms | 46.275 ms | 12.723 ms | 16.422 ms | 4.893 ms | 1.896 ms |
| interpolate! NUFFT | Float32 256^3 | 3.806 s | 2.221 s | 1.451 s | 1.054 s | 2.913 s | 1.554 s | 865.515 ms | 533.852 ms | — | 72.243 ms | 26.214 ms | 17.666 ms |
| interpolate! NUFFT | Float32 512^3 | — | — | — | — | 24.860 s | 13.310 s | 7.681 s | 4.948 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 17.897 ms | 10.623 ms | 7.107 ms | 5.480 ms | 12.193 ms | 6.514 ms | 3.783 ms | 2.565 ms | 1.847 ms | 4.302 ms | 2.275 ms | 425.724 μs |
| interpolate! NUFFT | Float64 128^3 | 456.351 ms | 275.340 ms | 209.942 ms | 177.430 ms | 223.598 ms | 127.076 ms | 84.158 ms | 79.636 ms | 25.361 ms | 18.237 ms | 8.627 ms | 5.522 ms |
| interpolate! NUFFT | Float64 256^3 | 4.178 s | 2.527 s | 1.822 s | 1.457 s | 2.040 s | 1.244 s | 874.946 ms | 740.668 ms | — | 118.516 ms | 56.632 ms | 47.700 ms |
| interpolate! NUFFT | Float64 512^3 | — | — | — | — | 24.830 s | 14.205 s | 8.754 s | 9.471 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 24.681 ms | 15.168 ms | 11.037 ms | 9.321 ms | 17.690 ms | 9.978 ms | 5.817 ms | 4.412 ms | 3.417 ms | 6.116 ms | 3.003 ms | 932.690 μs |
| interpolate! trilinear | Float32 128^3 | 2.040 ms | 1.064 ms | 548.762 μs | 298.410 μs | 1.327 ms | 666.057 μs | 337.324 μs | 184.262 μs | 255.582 μs | 1.719 ms | 1.094 ms | 64.201 μs |
| interpolate! trilinear | Float32 256^3 | 58.965 ms | 31.153 ms | 16.962 ms | 9.612 ms | 14.418 ms | 7.110 ms | 3.571 ms | 1.813 ms | — | 3.594 ms | 1.280 ms | 256.673 μs |
| interpolate! trilinear | Float32 512^3 | — | — | — | — | 436.871 ms | 236.005 ms | 124.909 ms | 61.150 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 229.927 μs | 130.069 μs | 79.441 μs | 55.421 μs | 147.141 μs | 81.531 μs | 47.280 μs | 33.500 μs | 65.160 μs | 1.448 ms | 957.585 μs | 58.660 μs |
| interpolate! trilinear | Float64 128^3 | 2.701 ms | 1.303 ms | 684.250 μs | 376.231 μs | 1.356 ms | 689.867 μs | 360.754 μs | 189.523 μs | 325.503 μs | 1.772 ms | 1.092 ms | 80.961 μs |
| interpolate! trilinear | Float64 256^3 | 63.559 ms | 34.975 ms | 21.773 ms | 14.148 ms | 33.955 ms | 16.857 ms | 8.395 ms | 4.198 ms | — | 4.014 ms | 1.595 ms | 409.324 μs |
| interpolate! trilinear | Float64 512^3 | — | — | — | — | 434.468 ms | 244.549 ms | 130.859 ms | 68.471 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 243.070 μs | 135.937 μs | 83.635 μs | 59.224 μs | 161.051 μs | 87.001 μs | 50.410 μs | 33.890 μs | 65.930 μs | 1.530 ms | 1.083 ms | 62.711 μs |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.254 ms | 7.184 ms | 7.518 ms | 8.042 ms | 6.960 ms | 4.943 ms | 6.179 ms | 6.352 ms | 2.099 ms | 27.761 ms | 1.656 ms | 286.353 μs |
| co-spectrum vec.vec | Float32 256^3 | 67.299 ms | 48.661 ms | 44.719 ms | 41.361 ms | 55.764 ms | 37.008 ms | 32.961 ms | 31.397 ms | — | 97.666 ms | 3.211 ms | 962.370 μs |
| co-spectrum vec.vec | Float32 512^3 | — | — | — | — | 441.848 ms | 267.260 ms | 191.978 ms | 158.050 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.066 ms | 1.312 ms | 1.499 ms | 1.608 ms | 905.038 μs | 936.859 μs | 1.232 ms | 1.397 ms | 491.824 μs | 17.761 ms | 1.383 ms | 173.231 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.657 ms | 6.773 ms | 6.126 ms | 5.353 ms | 7.257 ms | 5.152 ms | 4.654 ms | 4.690 ms | 2.194 ms | 29.708 ms | 29.468 ms | 372.083 μs |
| co-spectrum vec.vec | Float64 256^3 | 69.632 ms | 48.804 ms | 36.231 ms | 30.082 ms | 59.010 ms | 36.719 ms | 28.034 ms | 23.805 ms | — | 109.563 ms | 66.321 ms | 1.306 ms |
| co-spectrum vec.vec | Float64 512^3 | — | — | — | — | 475.152 ms | 280.928 ms | 184.413 ms | 133.066 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.085 ms | 825.029 μs | 980.776 μs | 1.003 ms | 938.768 μs | 725.347 μs | 884.669 μs | 962.570 μs | 482.135 μs | 16.075 ms | 16.001 ms | 181.622 μs |
| cov vector | Float32 128^3 | — | — | — | — | 1.142 ms | 584.585 μs | 306.433 μs | 192.102 μs | — | — | — | 265.642 μs |
| cov vector | Float32 256^3 | — | — | — | — | 12.396 ms | 7.752 ms | 4.958 ms | 4.828 ms | — | — | — | 979.710 μs |
| cov vector | Float32 512^3 | — | — | — | — | 92.899 ms | 64.693 ms | 55.364 ms | 55.754 ms | — | — | — | — |
| cov vector | Float32 64^3 | — | — | — | — | 149.521 μs | 85.641 μs | 51.450 μs | 43.890 μs | — | — | — | 218.762 μs |
| cov vector | Float64 128^3 | — | — | — | — | 2.243 ms | 1.134 ms | 580.117 μs | 346.734 μs | — | — | — | 378.574 μs |
| cov vector | Float64 256^3 | — | — | — | — | 24.081 ms | 14.654 ms | 12.405 ms | 12.622 ms | — | — | — | 1.549 ms |
| cov vector | Float64 512^3 | — | — | — | — | 182.235 ms | 129.383 ms | 111.393 ms | 111.743 ms | — | — | — | — |
| cov vector | Float64 64^3 | — | — | — | — | 282.643 μs | 157.001 μs | 89.331 μs | 66.161 μs | — | — | — | 236.143 μs |
| cross-correlation vec.vec | Float32 128^3 | 39.547 ms | 34.663 ms | 36.194 ms | 38.616 ms | 32.954 ms | 24.686 ms | 22.071 ms | 21.670 ms | 5.891 ms | 43.640 ms | 2.622 ms | 786.308 μs |
| cross-correlation vec.vec | Float32 256^3 | 474.252 ms | 310.305 ms | 279.929 ms | 270.474 ms | 373.026 ms | 263.050 ms | 190.521 ms | 175.493 ms | — | 186.915 ms | 10.470 ms | 5.935 ms |
| cross-correlation vec.vec | Float32 512^3 | — | — | — | — | 2.866 s | 2.020 s | 1.408 s | 1.187 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.749 ms | 5.378 ms | 6.182 ms | 6.182 ms | 3.874 ms | 3.576 ms | 3.740 ms | 3.572 ms | 1.025 ms | 20.682 ms | 1.467 ms | 291.763 μs |
| cross-correlation vec.vec | Float64 128^3 | 62.493 ms | 61.925 ms | 56.674 ms | 51.020 ms | 43.299 ms | 37.272 ms | 26.678 ms | 31.427 ms | 9.144 ms | 52.055 ms | 51.351 ms | 2.100 ms |
| cross-correlation vec.vec | Float64 256^3 | 694.984 ms | 487.096 ms | 402.316 ms | 373.900 ms | 567.618 ms | 375.879 ms | 264.971 ms | 261.569 ms | — | 217.471 ms | 137.382 ms | 15.042 ms |
| cross-correlation vec.vec | Float64 512^3 | — | — | — | — | 4.578 s | 2.976 s | 2.099 s | 1.755 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.865 ms | 5.997 ms | 5.802 ms | 6.028 ms | 4.218 ms | 3.372 ms | 3.369 ms | 3.344 ms | 1.557 ms | 20.881 ms | 23.884 ms | 326.204 μs |
| inner spectral | Float32 128^3 | 2.563 ms | 1.791 ms | 1.452 ms | 1.334 ms | 1.569 ms | 854.778 μs | 541.576 μs | 420.844 μs | 669.926 μs | 2.049 ms | 1.209 ms | 275.693 μs |
| inner spectral | Float32 256^3 | 23.278 ms | 18.210 ms | 16.587 ms | 15.600 ms | 13.069 ms | 8.947 ms | 7.392 ms | 7.219 ms | — | 3.999 ms | 1.750 ms | 788.268 μs |
| inner spectral | Float32 512^3 | — | — | — | — | 109.060 ms | 84.476 ms | 76.636 ms | 76.218 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 311.019 μs | 205.978 μs | 149.325 μs | 120.701 μs | 210.662 μs | 134.302 μs | 94.791 μs | 86.661 μs | 275.972 μs | 1.780 ms | 1.135 ms | 228.763 μs |
| inner spectral | Float64 128^3 | 4.413 ms | 3.674 ms | 3.246 ms | 3.123 ms | 1.930 ms | 1.170 ms | 777.278 μs | 689.238 μs | 811.337 μs | 2.410 ms | 1.363 ms | 367.373 μs |
| inner spectral | Float64 256^3 | 38.299 ms | 32.438 ms | 29.665 ms | 28.720 ms | 18.777 ms | 16.965 ms | 16.049 ms | 16.759 ms | — | 7.953 ms | 2.789 ms | 1.267 ms |
| inner spectral | Float64 512^3 | — | — | — | — | 133.458 ms | 135.191 ms | 128.418 ms | 130.547 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 320.843 μs | 216.120 μs | 156.316 μs | 128.354 μs | 237.692 μs | 150.921 μs | 102.231 μs | 95.991 μs | 293.003 μs | 1.765 ms | 1.138 ms | 246.313 μs |
| inner vec.vec | Float32 128^3 | 1.342 ms | 990.184 μs | 839.085 μs | 784.529 μs | 374.433 μs | 195.131 μs | 100.011 μs | 73.471 μs | 308.353 μs | 1.623 ms | 794.094 μs | 114.261 μs |
| inner vec.vec | Float32 256^3 | 14.293 ms | 12.958 ms | 12.083 ms | 11.385 ms | 6.897 ms | 6.189 ms | 5.774 ms | 6.037 ms | — | 3.382 ms | 1.298 ms | 573.026 μs |
| inner vec.vec | Float32 512^3 | — | — | — | — | 61.142 ms | 57.479 ms | 55.392 ms | 56.012 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 70.561 μs | 40.413 μs | 21.692 μs | 15.246 μs | 46.280 μs | 25.260 μs | 14.800 μs | 9.761 μs | 98.731 μs | 1.278 ms | 774.243 μs | 73.080 μs |
| inner vec.vec | Float64 128^3 | 3.170 ms | 2.654 ms | 2.422 ms | 2.283 ms | 1.158 ms | 565.716 μs | 356.934 μs | 258.903 μs | 552.615 μs | 1.860 ms | 998.015 μs | 231.033 μs |
| inner vec.vec | Float64 256^3 | 27.690 ms | 25.846 ms | 24.166 ms | 22.893 ms | 14.757 ms | 13.693 ms | 13.033 ms | 13.285 ms | — | 5.634 ms | 2.038 ms | 1.067 ms |
| inner vec.vec | Float64 512^3 | — | — | — | — | 122.522 ms | 115.134 ms | 111.816 ms | 112.167 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 140.726 μs | 79.148 μs | 42.532 μs | 26.139 μs | 87.711 μs | 46.600 μs | 27.960 μs | 18.401 μs | 162.792 μs | 1.434 ms | 777.319 μs | 108.042 μs |
| integral scalar | Float32 128^3 | 111.663 μs | 62.237 μs | 31.233 μs | 20.314 μs | 71.831 μs | 37.090 μs | 19.290 μs | 13.190 μs | 228.932 μs | 1.318 ms | 1.144 ms | 98.771 μs |
| integral scalar | Float32 256^3 | 2.158 ms | 1.576 ms | 1.356 ms | 1.256 ms | 623.456 μs | 286.923 μs | 145.832 μs | 99.481 μs | — | 9.002 ms | 2.302 ms | 251.372 μs |
| integral scalar | Float32 512^3 | — | — | — | — | 11.709 ms | 9.173 ms | 8.935 ms | 8.913 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 9.716 μs | 6.790 μs | 5.853 μs | 6.149 μs | 7.242 μs | 4.873 μs | 3.986 μs | 5.316 μs | 95.301 μs | 1.534 ms | 899.409 μs | 79.381 μs |
| integral scalar | Float64 128^3 | 237.317 μs | 131.226 μs | 68.405 μs | 39.071 μs | 121.692 μs | 63.921 μs | 34.441 μs | 23.280 μs | 221.812 μs | 2.553 ms | 1.192 ms | 95.681 μs |
| integral scalar | Float64 256^3 | 4.624 ms | 3.807 ms | 3.490 ms | 3.241 ms | 2.080 ms | 1.123 ms | 867.189 μs | 975.770 μs | — | 10.817 ms | 2.694 ms | 262.733 μs |
| integral scalar | Float64 512^3 | — | — | — | — | 23.581 ms | 18.577 ms | 17.855 ms | 18.062 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.823 μs | 13.214 μs | 8.356 μs | 8.211 μs | 15.290 μs | 8.200 μs | 6.062 μs | 5.790 μs | 95.391 μs | 1.583 ms | 853.383 μs | 80.791 μs |
| integral spectral vec | Float32 128^3 | 73.574 ns | 68.827 ns | 68.706 ns | 69.278 ns | 70.031 ns | 68.178 ns | 70.391 ns | 69.694 ns | — | — | 847.189 μs | 46.790 μs |
| integral spectral vec | Float32 256^3 | 73.413 ns | 68.980 ns | 69.976 ns | 69.051 ns | 70.401 ns | 68.853 ns | 70.954 ns | 69.827 ns | — | — | 812.731 μs | 45.430 μs |
| integral spectral vec | Float32 512^3 | — | — | — | — | 71.201 ns | 72.100 ns | 73.399 ns | 73.135 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 72.717 ns | 71.669 ns | 68.260 ns | 68.346 ns | 69.723 ns | 68.066 ns | 70.863 ns | 71.529 ns | — | — | 833.215 μs | 48.581 μs |
| integral spectral vec | Float64 128^3 | 75.348 ns | 70.247 ns | 71.222 ns | 70.787 ns | 75.135 ns | 72.688 ns | 75.515 ns | 74.231 ns | — | — | 832.384 μs | 49.231 μs |
| integral spectral vec | Float64 256^3 | 76.678 ns | 71.125 ns | 71.996 ns | 72.808 ns | 76.771 ns | 75.860 ns | 76.359 ns | 75.407 ns | — | — | 808.714 μs | 46.451 μs |
| integral spectral vec | Float64 512^3 | — | — | — | — | 78.427 ns | 78.118 ns | 80.629 ns | 79.682 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 72.326 ns | 69.628 ns | 69.560 ns | 70.826 ns | 77.699 ns | 72.300 ns | 79.164 ns | 73.910 ns | — | — | 842.906 μs | 46.371 μs |
| l2norm vec | Float32 128^3 | 640.793 μs | 338.018 μs | 186.032 μs | 92.844 μs | 250.773 μs | 126.192 μs | 64.200 μs | 41.250 μs | 196.632 μs | 1.582 ms | 854.011 μs | 80.941 μs |
| l2norm vec | Float32 256^3 | 8.328 ms | 6.167 ms | 5.599 ms | 5.442 ms | 4.305 ms | 2.964 ms | 2.030 ms | 2.024 ms | — | 3.219 ms | 1.301 ms | 343.224 μs |
| l2norm vec | Float32 512^3 | — | — | — | — | 41.460 ms | 30.362 ms | 26.668 ms | 27.134 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 50.794 μs | 27.610 μs | 15.886 μs | 11.830 μs | 31.351 μs | 16.490 μs | 9.460 μs | 7.190 μs | 85.641 μs | 1.361 ms | 756.839 μs | 83.061 μs |
| l2norm vec | Float64 128^3 | 1.712 ms | 1.077 ms | 827.080 μs | 779.411 μs | 502.514 μs | 252.052 μs | 125.802 μs | 80.231 μs | 344.333 μs | 1.876 ms | 978.559 μs | 143.271 μs |
| l2norm vec | Float64 256^3 | 15.793 ms | 12.600 ms | 11.618 ms | 11.037 ms | 11.129 ms | 6.709 ms | 5.560 ms | 5.584 ms | — | 5.670 ms | 1.957 ms | 601.196 μs |
| l2norm vec | Float64 512^3 | — | — | — | — | 66.898 ms | 62.106 ms | 54.605 ms | 54.754 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 94.189 μs | 53.113 μs | 28.482 μs | 18.489 μs | 54.831 μs | 32.341 μs | 17.030 μs | 10.930 μs | 134.871 μs | 1.402 ms | 773.034 μs | 111.662 μs |
| lpnorm vec Inf | Float32 128^3 | 1.389 ms | 1.370 ms | 1.146 ms | 1.040 ms | 457.545 μs | 408.884 μs | 339.924 μs | 322.683 μs | 592.145 μs | 3.080 ms | 1.319 ms | 136.582 μs |
| lpnorm vec Inf | Float32 256^3 | 22.791 ms | 14.822 ms | 12.193 ms | 11.084 ms | 8.232 ms | 7.710 ms | 7.867 ms | 8.434 ms | — | 13.216 ms | 3.421 ms | 589.796 μs |
| lpnorm vec Inf | Float32 512^3 | — | — | — | — | 76.470 ms | 69.399 ms | 75.074 ms | 70.576 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 98.887 μs | 92.210 μs | 73.501 μs | 78.929 μs | 61.181 μs | 49.261 μs | 41.580 μs | 42.341 μs | 155.751 μs | 1.641 ms | 964.230 μs | 104.291 μs |
| lpnorm vec Inf | Float64 128^3 | 3.310 ms | 3.191 ms | 2.602 ms | 2.600 ms | 1.239 ms | 1.050 ms | 939.710 μs | 1.010 ms | 660.476 μs | 3.883 ms | 1.668 ms | 231.382 μs |
| lpnorm vec Inf | Float64 256^3 | 47.266 ms | 31.386 ms | 24.155 ms | 22.468 ms | 17.095 ms | 15.533 ms | 15.776 ms | 16.111 ms | — | 14.730 ms | 5.382 ms | 969.430 μs |
| lpnorm vec Inf | Float64 512^3 | — | — | — | — | 149.403 ms | 168.664 ms | 141.742 ms | 139.058 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 238.281 μs | 179.555 μs | 154.396 μs | 145.295 μs | 111.541 μs | 93.331 μs | 76.440 μs | 72.600 μs | 166.092 μs | 1.711 ms | 1.005 ms | 122.612 μs |
| maximum scalar | Float32 128^3 | 345.259 μs | 177.509 μs | 92.029 μs | 51.200 μs | 238.222 μs | 118.181 μs | 60.781 μs | 33.041 μs | 223.322 μs | 2.331 ms | 1.146 ms | 95.411 μs |
| maximum scalar | Float32 256^3 | 2.903 ms | 1.818 ms | 1.454 ms | 1.335 ms | 1.874 ms | 937.129 μs | 495.515 μs | 243.643 μs | — | 9.121 ms | 2.319 ms | 248.802 μs |
| maximum scalar | Float32 512^3 | — | — | — | — | 30.997 ms | 15.120 ms | 8.906 ms | 8.030 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 43.017 μs | 24.700 μs | 14.813 μs | 11.942 μs | 29.571 μs | 15.801 μs | 9.170 μs | 6.840 μs | 101.731 μs | 1.564 ms | 922.422 μs | 78.651 μs |
| maximum scalar | Float64 128^3 | 547.286 μs | 291.499 μs | 144.142 μs | 79.381 μs | 446.844 μs | 222.422 μs | 113.912 μs | 59.601 μs | 244.072 μs | 2.772 ms | 1.301 ms | 102.591 μs |
| maximum scalar | Float64 256^3 | 6.082 ms | 4.302 ms | 3.627 ms | 3.355 ms | 4.094 ms | 2.061 ms | 1.125 ms | 811.389 μs | — | 12.659 ms | 3.329 ms | 290.963 μs |
| maximum scalar | Float64 512^3 | — | — | — | — | 46.466 ms | 26.948 ms | 18.625 ms | 17.379 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 66.519 μs | 37.472 μs | 20.447 μs | 14.675 μs | 55.480 μs | 29.381 μs | 16.020 μs | 10.120 μs | 99.451 μs | 1.634 ms | 947.833 μs | 98.891 μs |
| maximum(norm) vec | Float32 128^3 | 1.840 ms | 927.308 μs | 474.221 μs | 246.021 μs | 773.627 μs | 391.054 μs | 197.472 μs | 105.661 μs | — | — | 1.234 ms | 103.211 μs |
| maximum(norm) vec | Float32 256^3 | 15.152 ms | 8.494 ms | 5.995 ms | 5.604 ms | 7.111 ms | 3.816 ms | 2.129 ms | 2.154 ms | — | — | 2.782 ms | 369.544 μs |
| maximum(norm) vec | Float32 512^3 | — | — | — | — | 64.486 ms | 37.598 ms | 29.669 ms | 28.281 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 225.159 μs | 118.554 μs | 62.180 μs | 48.872 μs | 96.730 μs | 50.231 μs | 26.270 μs | 15.450 μs | — | — | 920.168 μs | 79.361 μs |
| maximum(norm) vec | Float64 128^3 | 5.345 ms | 2.715 ms | 1.393 ms | 846.954 μs | 1.665 ms | 796.468 μs | 400.334 μs | 213.203 μs | — | — | 1.571 ms | 222.872 μs |
| maximum(norm) vec | Float64 256^3 | 43.178 ms | 22.282 ms | 13.330 ms | 11.568 ms | 14.004 ms | 8.156 ms | 6.023 ms | 5.847 ms | — | — | 4.860 ms | 1.049 ms |
| maximum(norm) vec | Float64 512^3 | — | — | — | — | 114.390 ms | 74.467 ms | 58.167 ms | 56.904 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 651.615 μs | 337.108 μs | 170.646 μs | 90.136 μs | 197.252 μs | 101.591 μs | 52.221 μs | 28.501 μs | — | — | 979.833 μs | 104.261 μs |
| mean spectral vec | Float32 128^3 | 71.740 ns | 71.533 ns | 71.579 ns | 72.110 ns | 73.136 ns | 71.863 ns | 72.920 ns | 73.556 ns | — | — | 820.577 μs | 45.680 μs |
| mean spectral vec | Float32 256^3 | 72.239 ns | 72.320 ns | 72.756 ns | 72.872 ns | 73.371 ns | 72.606 ns | 74.111 ns | 73.573 ns | — | — | 812.941 μs | 49.570 μs |
| mean spectral vec | Float32 512^3 | — | — | — | — | 73.782 ns | 75.608 ns | 75.674 ns | 77.383 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 77.463 ns | 71.234 ns | 71.368 ns | 71.759 ns | 72.498 ns | 71.687 ns | 74.318 ns | 75.551 ns | — | — | 833.055 μs | 45.440 μs |
| mean spectral vec | Float64 128^3 | 77.758 ns | 73.848 ns | 74.286 ns | 74.398 ns | 83.330 ns | 78.090 ns | 83.730 ns | 76.441 ns | — | — | 814.812 μs | 52.090 μs |
| mean spectral vec | Float64 256^3 | 79.716 ns | 74.563 ns | 75.460 ns | 76.613 ns | 84.665 ns | 79.485 ns | 85.630 ns | 77.933 ns | — | — | 848.819 μs | 50.750 μs |
| mean spectral vec | Float64 512^3 | — | — | — | — | 86.194 ns | 83.431 ns | 88.723 ns | 81.477 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 73.504 ns | 73.021 ns | 72.737 ns | 73.951 ns | 86.137 ns | 77.314 ns | 87.904 ns | 75.661 ns | — | — | 830.467 μs | 44.721 μs |
| mean vector | Float32 128^3 | 521.620 μs | 319.670 μs | 194.991 μs | 114.663 μs | 205.022 μs | 122.861 μs | 69.230 μs | 52.771 μs | 633.756 μs | 4.808 ms | 1.887 ms | 194.722 μs |
| mean vector | Float32 256^3 | 7.827 ms | 6.072 ms | 5.559 ms | 5.436 ms | 3.582 ms | 2.772 ms | 2.432 ms | 2.481 ms | — | 16.657 ms | 5.531 ms | 654.346 μs |
| mean vector | Float32 512^3 | — | — | — | — | 32.822 ms | 27.927 ms | 26.986 ms | 27.409 ms | — | — | — | — |
| mean vector | Float32 64^3 | 49.165 μs | 34.264 μs | 25.674 μs | 31.341 μs | 31.210 μs | 22.080 μs | 18.121 μs | 22.370 μs | 162.362 μs | 1.846 ms | 1.302 ms | 158.931 μs |
| mean vector | Float64 128^3 | 1.648 ms | 1.053 ms | 849.643 μs | 793.726 μs | 417.104 μs | 216.003 μs | 117.221 μs | 94.911 μs | 657.486 μs | 5.195 ms | 1.836 ms | 213.142 μs |
| mean vector | Float64 256^3 | 14.983 ms | 12.972 ms | 11.806 ms | 11.316 ms | 7.527 ms | 6.699 ms | 6.594 ms | 6.683 ms | — | 17.799 ms | 6.369 ms | 715.868 μs |
| mean vector | Float64 512^3 | — | — | — | — | 58.964 ms | 56.619 ms | 54.620 ms | 54.996 ms | — | — | — | — |
| mean vector | Float64 64^3 | 92.415 μs | 63.766 μs | 41.668 μs | 40.850 μs | 54.950 μs | 37.640 μs | 26.710 μs | 29.790 μs | 156.311 μs | 1.913 ms | 1.281 ms | 171.602 μs |
| mean(det) tensor | Float32 128^3 | 2.495 ms | 1.968 ms | 1.694 ms | 1.532 ms | 781.697 μs | 358.824 μs | 199.662 μs | 122.372 μs | — | — | 1.280 ms | 218.912 μs |
| mean(det) tensor | Float32 256^3 | 24.807 ms | 21.499 ms | 19.098 ms | 17.978 ms | 16.213 ms | 11.693 ms | 10.346 ms | 10.361 ms | — | — | 3.413 ms | 848.598 μs |
| mean(det) tensor | Float32 512^3 | — | — | — | — | 106.485 ms | 89.590 ms | 84.088 ms | 84.820 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 103.122 μs | 61.466 μs | 29.994 μs | 21.224 μs | 67.901 μs | 35.941 μs | 23.420 μs | 15.290 μs | — | — | 937.045 μs | 87.581 μs |
| mean(det) tensor | Float64 128^3 | 5.384 ms | 4.754 ms | 4.222 ms | 3.863 ms | 2.517 ms | 1.553 ms | 1.205 ms | 1.213 ms | — | — | 1.491 ms | 285.863 μs |
| mean(det) tensor | Float64 256^3 | 46.354 ms | 44.532 ms | 38.506 ms | 37.166 ms | 30.310 ms | 23.708 ms | 21.572 ms | 21.536 ms | — | — | 4.560 ms | 1.534 ms |
| mean(det) tensor | Float64 512^3 | — | — | — | — | 206.413 ms | 174.152 ms | 168.925 ms | 169.519 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 233.464 μs | 129.918 μs | 74.662 μs | 41.508 μs | 132.061 μs | 67.351 μs | 36.381 μs | 28.760 μs | — | — | 972.637 μs | 96.331 μs |
| mean(norm) vec | Float32 128^3 | 1.589 ms | 806.356 μs | 407.919 μs | 212.917 μs | 608.975 μs | 301.983 μs | 159.471 μs | 84.271 μs | — | — | 538.869 μs | 106.141 μs |
| mean(norm) vec | Float32 256^3 | 13.152 ms | 7.866 ms | 5.982 ms | 5.545 ms | 6.143 ms | 3.415 ms | 2.058 ms | 2.152 ms | — | — | 2.833 ms | 363.313 μs |
| mean(norm) vec | Float32 512^3 | — | — | — | — | 57.918 ms | 35.979 ms | 29.473 ms | 28.345 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 193.009 μs | 99.359 μs | 53.467 μs | 31.969 μs | 76.081 μs | 38.490 μs | 21.010 μs | 12.980 μs | — | — | 921.051 μs | 81.840 μs |
| mean(norm) vec | Float64 128^3 | 5.283 ms | 2.668 ms | 1.367 ms | 852.780 μs | 1.439 ms | 721.887 μs | 364.034 μs | 195.972 μs | — | — | 1.332 ms | 212.442 μs |
| mean(norm) vec | Float64 256^3 | 42.797 ms | 21.618 ms | 13.196 ms | 11.503 ms | 13.427 ms | 8.145 ms | 6.017 ms | 5.812 ms | — | — | 4.325 ms | 966.340 μs |
| mean(norm) vec | Float64 512^3 | — | — | — | — | 109.215 ms | 71.071 ms | 57.901 ms | 56.729 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 644.557 μs | 332.750 μs | 168.447 μs | 89.317 μs | 178.602 μs | 92.931 μs | 48.050 μs | 26.281 μs | — | — | 957.695 μs | 96.611 μs |
| mean(tr) tensor | Float32 128^3 | 376.803 μs | 234.813 μs | 139.321 μs | 73.191 μs | 195.212 μs | 97.310 μs | 50.060 μs | 36.710 μs | — | — | 1.200 ms | 105.871 μs |
| mean(tr) tensor | Float32 256^3 | 6.684 ms | 6.358 ms | 5.667 ms | 5.460 ms | 3.201 ms | 2.374 ms | 2.125 ms | 2.220 ms | — | — | 2.699 ms | 348.183 μs |
| mean(tr) tensor | Float32 512^3 | — | — | — | — | 33.531 ms | 28.981 ms | 27.592 ms | 28.088 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 34.871 μs | 18.654 μs | 11.294 μs | 10.156 μs | 25.790 μs | 13.030 μs | 7.290 μs | 6.370 μs | — | — | 910.276 μs | 84.631 μs |
| mean(tr) tensor | Float64 128^3 | 1.325 ms | 985.412 μs | 838.504 μs | 748.239 μs | 362.703 μs | 193.952 μs | 100.731 μs | 71.461 μs | — | — | 1.170 ms | 138.301 μs |
| mean(tr) tensor | Float64 256^3 | 13.247 ms | 13.083 ms | 11.902 ms | 11.275 ms | 6.779 ms | 6.554 ms | 6.318 ms | 6.255 ms | — | — | 3.285 ms | 597.786 μs |
| mean(tr) tensor | Float64 512^3 | — | — | — | — | 68.967 ms | 57.667 ms | 56.047 ms | 56.480 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 67.856 μs | 37.556 μs | 20.285 μs | 15.147 μs | 42.880 μs | 24.350 μs | 14.210 μs | 9.700 μs | — | — | 921.594 μs | 85.131 μs |
| radial_correlation vec | Float32 128^3 | 37.712 ms | 33.033 ms | 35.793 ms | 36.040 ms | 30.609 ms | 22.754 ms | 21.617 ms | 20.870 ms | 5.783 ms | 42.875 ms | 2.515 ms | 755.908 μs |
| radial_correlation vec | Float32 256^3 | 447.565 ms | 308.865 ms | 277.883 ms | 264.189 ms | 354.668 ms | 255.710 ms | 184.530 ms | 170.833 ms | — | 185.439 ms | 10.286 ms | 5.607 ms |
| radial_correlation vec | Float32 512^3 | — | — | — | — | 2.734 s | 1.898 s | 1.315 s | 1.169 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.485 ms | 5.199 ms | 5.976 ms | 5.911 ms | 3.552 ms | 3.331 ms | 3.596 ms | 3.569 ms | 1.010 ms | 19.917 ms | 1.555 ms | 272.113 μs |
| radial_correlation vec | Float64 128^3 | 60.402 ms | 62.099 ms | 54.644 ms | 51.117 ms | 38.801 ms | 38.596 ms | 31.664 ms | 30.675 ms | 9.025 ms | 52.060 ms | 47.229 ms | 2.017 ms |
| radial_correlation vec | Float64 256^3 | 673.902 ms | 474.417 ms | 394.981 ms | 361.825 ms | 552.245 ms | 350.632 ms | 282.552 ms | 255.200 ms | — | 219.151 ms | 138.359 ms | 16.351 ms |
| radial_correlation vec | Float64 512^3 | — | — | — | — | 4.380 s | 2.802 s | 2.016 s | 1.717 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.555 ms | 5.140 ms | 5.663 ms | 5.733 ms | 3.834 ms | 3.278 ms | 3.305 ms | 3.015 ms | 1.413 ms | 21.203 ms | 23.553 ms | 340.623 μs |
| radial_spectrum vec | Float32 128^3 | 7.687 ms | 7.368 ms | 8.086 ms | 8.080 ms | 6.335 ms | 4.759 ms | 5.771 ms | 6.324 ms | 1.415 ms | 27.166 ms | 1.792 ms | 284.453 μs |
| radial_spectrum vec | Float32 256^3 | 61.536 ms | 48.600 ms | 45.891 ms | 43.702 ms | 50.106 ms | 34.104 ms | 31.551 ms | 31.543 ms | — | 96.772 ms | 3.246 ms | 974.990 μs |
| radial_spectrum vec | Float32 512^3 | — | — | — | — | 399.939 ms | 240.860 ms | 181.153 ms | 159.044 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 998.613 μs | 1.333 ms | 1.599 ms | 1.621 ms | 821.537 μs | 913.750 μs | 1.181 ms | 1.420 ms | 344.443 μs | 16.995 ms | 1.190 ms | 170.391 μs |
| radial_spectrum vec | Float64 128^3 | 7.731 ms | 6.612 ms | 5.934 ms | 5.548 ms | 6.549 ms | 4.657 ms | 4.585 ms | 4.540 ms | 1.515 ms | 29.791 ms | 28.854 ms | 370.603 μs |
| radial_spectrum vec | Float64 256^3 | 62.255 ms | 46.066 ms | 36.465 ms | 30.301 ms | 51.959 ms | 32.393 ms | 25.699 ms | 22.701 ms | — | 110.504 ms | 67.077 ms | 1.392 ms |
| radial_spectrum vec | Float64 512^3 | — | — | — | — | 414.419 ms | 255.987 ms | 164.005 ms | 123.458 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 1.008 ms | 774.067 μs | 1.104 ms | 1.102 ms | 851.157 μs | 708.077 μs | 882.439 μs | 924.969 μs | 380.613 μs | 16.740 ms | 15.470 ms | 184.712 μs |
| var scalar | Float32 128^3 | — | — | — | — | 141.722 μs | 76.041 μs | 40.801 μs | 27.890 μs | — | — | — | 132.242 μs |
| var scalar | Float32 256^3 | — | — | — | — | 1.318 ms | 613.636 μs | 346.034 μs | 199.002 μs | — | — | — | 465.215 μs |
| var scalar | Float32 512^3 | — | — | — | — | 27.803 ms | 20.503 ms | 18.020 ms | 17.927 ms | — | — | — | — |
| var scalar | Float32 64^3 | — | — | — | — | 15.180 μs | 9.250 μs | 7.180 μs | 9.090 μs | — | — | — | 123.202 μs |
| var scalar | Float64 128^3 | — | — | — | — | 246.422 μs | 130.271 μs | 75.780 μs | 48.221 μs | — | — | — | 150.412 μs |
| var scalar | Float64 256^3 | — | — | — | — | 4.507 ms | 2.440 ms | 1.772 ms | 1.829 ms | — | — | — | 503.375 μs |
| var scalar | Float64 512^3 | — | — | — | — | 48.963 ms | 38.871 ms | 36.148 ms | 36.150 ms | — | — | — | — |
| var scalar | Float64 64^3 | — | — | — | — | 31.240 μs | 17.160 μs | 10.730 μs | 11.030 μs | — | — | — | 131.142 μs |
| var spectral scalar | Float32 128^3 | — | — | — | — | 94.521 μs | 62.601 μs | 43.720 μs | 45.090 μs | — | — | — | 167.002 μs |
| var spectral scalar | Float32 256^3 | — | — | — | — | 789.518 μs | 466.625 μs | 294.733 μs | 236.962 μs | — | — | — | 311.783 μs |
| var spectral scalar | Float32 512^3 | — | — | — | — | 13.040 ms | 10.187 ms | 10.540 ms | 10.864 ms | — | — | — | — |
| var spectral scalar | Float32 64^3 | — | — | — | — | 12.381 μs | 8.440 μs | 7.780 μs | 8.650 μs | — | — | — | 169.552 μs |
| var spectral scalar | Float64 128^3 | — | — | — | — | 148.542 μs | 88.031 μs | 60.621 μs | 63.341 μs | — | — | — | 179.841 μs |
| var spectral scalar | Float64 256^3 | — | — | — | — | 2.216 ms | 1.379 ms | 1.055 ms | 1.095 ms | — | — | — | 350.184 μs |
| var spectral scalar | Float64 512^3 | — | — | — | — | 20.898 ms | 20.825 ms | 20.393 ms | 20.461 ms | — | — | — | — |
| var spectral scalar | Float64 64^3 | — | — | — | — | 20.590 μs | 13.110 μs | 10.080 μs | 11.750 μs | — | — | — | 174.301 μs |
| weighted_inner vec | Float32 128^3 | 12.776 ms | 12.629 ms | 12.608 ms | 12.786 ms | 10.415 ms | 10.354 ms | 10.385 ms | 10.423 ms | — | — | 1.428 ms | 138.411 μs |
| weighted_inner vec | Float32 256^3 | 100.807 ms | 100.234 ms | 99.130 ms | 100.881 ms | 81.571 ms | 81.501 ms | 81.586 ms | 81.696 ms | — | — | 4.280 ms | 643.566 μs |
| weighted_inner vec | Float32 512^3 | — | — | — | — | 647.479 ms | 646.493 ms | 647.798 ms | 647.763 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.629 ms | 1.624 ms | 1.626 ms | 1.629 ms | 1.338 ms | 1.283 ms | 1.285 ms | 1.312 ms | — | — | 1.020 ms | 93.240 μs |
| weighted_inner vec | Float64 128^3 | 13.991 ms | 13.956 ms | 13.886 ms | 13.759 ms | 10.893 ms | 11.026 ms | 10.913 ms | 10.977 ms | — | — | 1.679 ms | 168.302 μs |
| weighted_inner vec | Float64 256^3 | 110.973 ms | 111.552 ms | 111.245 ms | 108.115 ms | 85.681 ms | 86.062 ms | 85.829 ms | 85.689 ms | — | — | 5.232 ms | 1.093 ms |
| weighted_inner vec | Float64 512^3 | — | — | — | — | 680.612 ms | 681.770 ms | 682.042 ms | 680.947 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.725 ms | 1.725 ms | 1.722 ms | 1.715 ms | 1.409 ms | 1.351 ms | 1.389 ms | 1.433 ms | — | — | 1.040 ms | 95.351 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.869 ms | 12.646 ms | 12.697 ms | 12.786 ms | 10.393 ms | 10.343 ms | 10.343 ms | 10.409 ms | — | — | 1.362 ms | 155.891 μs |
| weighted_inner vec.vec | Float32 256^3 | 101.877 ms | 100.494 ms | 99.619 ms | 101.362 ms | 81.680 ms | 81.608 ms | 81.708 ms | 81.815 ms | — | — | 4.195 ms | 841.659 μs |
| weighted_inner vec.vec | Float32 512^3 | — | — | — | — | 648.821 ms | 647.870 ms | 648.800 ms | 648.397 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.632 ms | 1.626 ms | 1.628 ms | 1.599 ms | 1.342 ms | 1.287 ms | 1.293 ms | 1.317 ms | — | — | 1.001 ms | 91.181 μs |
| weighted_inner vec.vec | Float64 128^3 | 14.076 ms | 14.115 ms | 14.233 ms | 13.824 ms | 10.942 ms | 11.590 ms | 10.947 ms | 10.972 ms | — | — | 1.584 ms | 254.663 μs |
| weighted_inner vec.vec | Float64 256^3 | 112.210 ms | 112.428 ms | 114.038 ms | 110.747 ms | 85.999 ms | 86.386 ms | 86.179 ms | 86.072 ms | — | — | 5.332 ms | 1.539 ms |
| weighted_inner vec.vec | Float64 512^3 | — | — | — | — | 682.907 ms | 684.284 ms | 683.347 ms | 683.454 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.743 ms | 1.729 ms | 1.743 ms | 1.705 ms | 1.457 ms | 1.397 ms | 1.405 ms | 1.442 ms | — | — | 985.284 μs | 96.221 μs |

