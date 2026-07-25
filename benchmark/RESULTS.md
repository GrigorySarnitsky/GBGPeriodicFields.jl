# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-07-25 at commit `ce73a413` on Julia 1.12.6, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–256³) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The pre-swap archive columns (GTX 1070, RX 6700 XT) keep their pre-rewrite measurements — retired hardware is not re-swept; every live column (both CPUs, RX 7900 XTX, RTX 5070 Ti) is measured at the decision-38/39 rewrite. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh` plus the per-card / per-CPU archive in `benchmark/results/` (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `48b6254a @ 2026-07-22`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8; `5934a78c @ 2026-07-22`: GPU 7900XTX; `ce73a413 @ 2026-07-25`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI; unstamped (vintage in the prose above): GPU 1070, GPU 6700XT. ~10% jitter.

## fft

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 4.029 ms | 2.979 ms | 2.144 ms | 2.286 ms | 2.719 ms | 1.459 ms | 835.349 μs | 544.005 μs | — | — | — | — |
| to_physical scalar measure | Float32 256^3 | 70.669 ms | 39.135 ms | 41.008 ms | 38.313 ms | 46.286 ms | 25.661 ms | 22.267 ms | 19.495 ms | — | — | — | — |
| to_physical scalar measure | Float32 512^3 | — | — | — | — | 468.159 ms | 300.729 ms | 234.622 ms | 198.861 ms | — | — | — | — |
| to_physical scalar measure | Float32 64^3 | 379.762 μs | 239.143 μs | 166.345 μs | 174.205 μs | 278.131 μs | 157.122 μs | 97.301 μs | 70.631 μs | — | — | — | — |
| to_physical scalar measure | Float64 128^3 | 6.339 ms | 5.666 ms | 5.246 ms | 4.657 ms | 4.107 ms | 2.655 ms | 1.460 ms | 1.006 ms | — | — | — | — |
| to_physical scalar measure | Float64 256^3 | 130.934 ms | 77.228 ms | 81.269 ms | 80.228 ms | 95.436 ms | 64.630 ms | 51.129 ms | 44.297 ms | — | — | — | — |
| to_physical scalar measure | Float64 512^3 | — | — | — | — | 841.341 ms | 568.633 ms | 445.753 ms | 398.708 ms | — | — | — | — |
| to_physical scalar measure | Float64 64^3 | 550.138 μs | 384.916 μs | 254.230 μs | 269.289 μs | 358.233 μs | 202.932 μs | 127.052 μs | 98.001 μs | — | — | — | — |
| to_physical scalar | Float32 128^3 | 5.090 ms | 3.355 ms | 2.501 ms | 2.307 ms | 4.934 ms | 2.511 ms | 1.255 ms | 774.788 μs | 788.067 μs | 2.421 ms | 1.261 ms | 134.311 μs |
| to_physical scalar | Float32 256^3 | 121.444 ms | 68.555 ms | 51.504 ms | 42.019 ms | 182.033 ms | 94.840 ms | 55.860 ms | 35.949 ms | — | 7.945 ms | 2.307 ms | 1.084 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | 2.102 s | 1.117 s | 627.939 ms | 394.709 ms | — | — | 13.398 ms | — |
| to_physical scalar | Float32 64^3 | 393.312 μs | 254.738 μs | 177.742 μs | 169.864 μs | 315.401 μs | 176.802 μs | 102.191 μs | 69.511 μs | 124.402 μs | 1.497 ms | 1.071 ms | 105.051 μs |
| to_physical scalar | Float64 128^3 | 8.120 ms | 5.823 ms | 4.940 ms | 4.470 ms | 10.268 ms | 5.484 ms | 3.021 ms | 1.753 ms | 1.905 ms | 3.750 ms | 1.646 ms | 492.165 μs |
| to_physical scalar | Float64 256^3 | 153.418 ms | 86.677 ms | 84.769 ms | 78.209 ms | 111.065 ms | 73.075 ms | 53.555 ms | 46.712 ms | — | 14.463 ms | 5.748 ms | 3.841 ms |
| to_physical scalar | Float64 512^3 | — | — | — | — | 942.437 ms | 607.628 ms | 454.215 ms | 416.860 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 702.253 μs | 432.399 μs | 307.892 μs | 258.256 μs | 531.435 μs | 283.183 μs | 171.083 μs | 113.532 μs | 331.873 μs | 1.784 ms | 992.328 μs | 109.071 μs |
| to_physical vector measure | Float32 128^3 | 12.766 ms | 9.673 ms | 8.916 ms | 7.915 ms | 9.045 ms | 5.835 ms | 4.060 ms | 2.856 ms | — | — | — | — |
| to_physical vector measure | Float32 256^3 | 214.079 ms | 158.244 ms | 131.321 ms | 124.027 ms | 168.787 ms | 122.633 ms | 88.495 ms | 76.126 ms | — | — | — | — |
| to_physical vector measure | Float32 512^3 | — | — | — | — | 1.384 s | 932.930 ms | 723.610 ms | 604.622 ms | — | — | — | — |
| to_physical vector measure | Float32 64^3 | 1.243 ms | 846.687 μs | 565.090 μs | 477.502 μs | 876.133 μs | 483.075 μs | 294.993 μs | 201.622 μs | — | — | — | — |
| to_physical vector measure | Float64 128^3 | 39.710 ms | 19.225 ms | 24.054 ms | 28.588 ms | 26.521 ms | 15.838 ms | 13.690 ms | 12.533 ms | — | — | — | — |
| to_physical vector measure | Float64 256^3 | 394.501 ms | 287.104 ms | 246.423 ms | 233.583 ms | 307.730 ms | 211.974 ms | 168.869 ms | 154.384 ms | — | — | — | — |
| to_physical vector measure | Float64 512^3 | — | — | — | — | 2.487 s | 1.739 s | 1.339 s | 1.208 s | — | — | — | — |
| to_physical vector measure | Float64 64^3 | 2.216 ms | 1.775 ms | 1.270 ms | 1.164 ms | 1.125 ms | 682.167 μs | 422.835 μs | 308.723 μs | — | — | — | — |
| to_physical vector | Float32 128^3 | 15.103 ms | 11.836 ms | 8.416 ms | 7.502 ms | 14.330 ms | 10.306 ms | 5.541 ms | 3.800 ms | 2.507 ms | 4.595 ms | 1.724 ms | 319.323 μs |
| to_physical vector | Float32 256^3 | 365.291 ms | 269.022 ms | 173.624 ms | 151.640 ms | 582.018 ms | 407.172 ms | 219.790 ms | 164.563 ms | — | 14.844 ms | 5.773 ms | 3.485 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | 6.286 s | 4.281 s | 2.294 s | 1.657 s | — | — | 51.336 ms | — |
| to_physical vector | Float32 64^3 | 1.306 ms | 1.045 ms | 596.992 μs | 550.376 μs | 1.006 ms | 683.947 μs | 315.464 μs | 209.552 μs | 380.054 μs | 1.776 ms | 1.186 ms | 101.391 μs |
| to_physical vector | Float64 128^3 | 46.428 ms | 20.507 ms | 26.548 ms | 27.522 ms | 45.437 ms | 28.361 ms | 18.192 ms | 15.258 ms | 5.630 ms | 8.090 ms | 2.788 ms | 1.484 ms |
| to_physical vector | Float64 256^3 | 460.818 ms | 358.235 ms | 260.213 ms | 241.545 ms | 355.822 ms | 267.775 ms | 174.025 ms | 155.075 ms | — | 22.812 ms | 13.720 ms | 11.341 ms |
| to_physical vector | Float64 512^3 | — | — | — | — | 2.779 s | 2.119 s | 1.405 s | 1.256 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.619 ms | 2.147 ms | 1.646 ms | 1.216 ms | 1.628 ms | 1.133 ms | 562.287 μs | 426.484 μs | 811.437 μs | 2.301 ms | 1.271 ms | 213.912 μs |
| to_spectral scalar measure | Float32 128^3 | 3.676 ms | 2.364 ms | 1.542 ms | 1.608 ms | 2.755 ms | 1.443 ms | 788.899 μs | 468.005 μs | — | — | — | — |
| to_spectral scalar measure | Float32 256^3 | 64.792 ms | 32.427 ms | 35.643 ms | 32.348 ms | 48.340 ms | 26.780 ms | 22.733 ms | 18.111 ms | — | — | — | — |
| to_spectral scalar measure | Float32 512^3 | — | — | — | — | 453.112 ms | 277.381 ms | 203.301 ms | 169.759 ms | — | — | — | — |
| to_spectral scalar measure | Float32 64^3 | 365.235 μs | 209.243 μs | 132.354 μs | 137.319 μs | 269.771 μs | 146.081 μs | 84.851 μs | 56.080 μs | — | — | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.417 ms | 4.397 ms | 3.789 ms | 3.542 ms | 4.510 ms | 2.400 ms | 1.504 ms | 934.969 μs | — | — | — | — |
| to_spectral scalar measure | Float64 256^3 | 125.027 ms | 67.875 ms | 71.203 ms | 65.713 ms | 89.683 ms | 61.907 ms | 46.416 ms | 38.461 ms | — | — | — | — |
| to_spectral scalar measure | Float64 512^3 | — | — | — | — | 763.455 ms | 505.618 ms | 378.706 ms | 335.503 ms | — | — | — | — |
| to_spectral scalar measure | Float64 64^3 | 488.909 μs | 307.927 μs | 233.393 μs | 155.459 μs | 339.374 μs | 187.482 μs | 112.341 μs | 80.091 μs | — | — | — | — |
| to_spectral scalar | Float32 128^3 | 4.631 ms | 2.783 ms | 1.829 ms | 1.359 ms | 4.772 ms | 2.327 ms | 1.233 ms | 708.407 μs | 488.254 μs | 2.072 ms | 1.113 ms | 102.041 μs |
| to_spectral scalar | Float32 256^3 | 116.450 ms | 64.693 ms | 48.096 ms | 36.889 ms | 183.778 ms | 94.667 ms | 57.362 ms | 35.047 ms | — | 5.009 ms | 1.905 ms | 735.968 μs |
| to_spectral scalar | Float32 512^3 | — | — | — | — | 2.081 s | 1.090 s | 604.112 ms | 363.609 ms | — | — | 9.591 ms | — |
| to_spectral scalar | Float32 64^3 | 372.359 μs | 214.769 μs | 131.392 μs | 113.455 μs | 310.232 μs | 164.572 μs | 90.501 μs | 58.411 μs | 89.181 μs | 1.538 ms | 1.110 ms | 68.881 μs |
| to_spectral scalar | Float64 128^3 | 7.266 ms | 5.156 ms | 3.900 ms | 3.492 ms | 10.390 ms | 5.431 ms | 2.902 ms | 1.638 ms | 1.501 ms | 3.125 ms | 1.651 ms | 428.814 μs |
| to_spectral scalar | Float64 256^3 | 174.719 ms | 98.673 ms | 79.881 ms | 67.152 ms | 209.354 ms | 118.232 ms | 72.648 ms | 52.649 ms | — | 12.871 ms | 5.179 ms | 3.120 ms |
| to_spectral scalar | Float64 512^3 | — | — | — | — | 1.709 s | 957.900 ms | 587.080 ms | 431.760 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 660.845 μs | 375.644 μs | 246.524 μs | 187.733 μs | 513.785 μs | 267.733 μs | 154.032 μs | 95.111 μs | 265.683 μs | 1.745 ms | 1.077 ms | 94.241 μs |
| to_spectral vector measure | Float32 128^3 | 11.048 ms | 7.840 ms | 6.309 ms | 5.676 ms | 10.087 ms | 5.888 ms | 4.019 ms | 2.618 ms | — | — | — | — |
| to_spectral vector measure | Float32 256^3 | 194.942 ms | 138.599 ms | 108.318 ms | 104.246 ms | 167.347 ms | 112.203 ms | 80.366 ms | 66.226 ms | — | — | — | — |
| to_spectral vector measure | Float32 512^3 | — | — | — | — | 1.362 s | 879.967 ms | 608.308 ms | 514.740 ms | — | — | — | — |
| to_spectral vector measure | Float32 64^3 | 1.133 ms | 709.014 μs | 489.066 μs | 410.465 μs | 873.314 μs | 483.735 μs | 257.583 μs | 165.612 μs | — | — | — | — |
| to_spectral vector measure | Float64 128^3 | 36.748 ms | 15.038 ms | 18.304 ms | 13.894 ms | 28.257 ms | 16.684 ms | 12.535 ms | 7.287 ms | — | — | — | — |
| to_spectral vector measure | Float64 256^3 | 378.151 ms | 266.528 ms | 209.729 ms | 202.722 ms | 279.002 ms | 194.892 ms | 140.485 ms | 130.081 ms | — | — | — | — |
| to_spectral vector measure | Float64 512^3 | — | — | — | — | 2.237 s | 1.572 s | 1.142 s | 984.153 ms | — | — | — | — |
| to_spectral vector measure | Float64 64^3 | 1.673 ms | 1.521 ms | 887.037 μs | 648.760 μs | 1.041 ms | 626.697 μs | 359.484 μs | 273.813 μs | — | — | — | — |
| to_spectral vector | Float32 128^3 | 14.075 ms | 9.864 ms | 6.814 ms | 5.884 ms | 14.681 ms | 10.355 ms | 5.509 ms | 3.306 ms | 1.355 ms | 3.183 ms | 1.354 ms | 216.122 μs |
| to_spectral vector | Float32 256^3 | 353.409 ms | 258.328 ms | 153.782 ms | 128.389 ms | 574.726 ms | 396.230 ms | 212.417 ms | 151.052 ms | — | 11.819 ms | 3.512 ms | 2.216 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | 6.209 s | 4.244 s | 2.218 s | 1.586 s | — | — | 20.305 ms | — |
| to_spectral vector | Float32 64^3 | 1.296 ms | 931.449 μs | 509.295 μs | 432.093 μs | 975.704 μs | 648.107 μs | 285.444 μs | 179.012 μs | 230.522 μs | 1.566 ms | 924.065 μs | 76.781 μs |
| to_spectral vector | Float64 128^3 | 43.494 ms | 18.891 ms | 23.457 ms | 13.411 ms | 48.056 ms | 29.466 ms | 18.414 ms | 11.224 ms | 4.144 ms | 6.538 ms | 2.420 ms | 1.170 ms |
| to_spectral vector | Float64 256^3 | 515.584 ms | 385.138 ms | 244.471 ms | 223.678 ms | 634.234 ms | 447.621 ms | 251.764 ms | 195.780 ms | — | 20.041 ms | 11.730 ms | 9.181 ms |
| to_spectral vector | Float64 512^3 | — | — | — | — | 5.090 s | 3.599 s | 2.016 s | 1.592 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.288 ms | 1.711 ms | 1.039 ms | 825.169 μs | 1.536 ms | 1.065 ms | 514.596 μs | 348.983 μs | 596.836 μs | 2.151 ms | 1.215 ms | 198.892 μs |

## algebra

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 415.446 μs | 232.867 μs | 171.971 μs | 72.717 μs | 162.171 μs | 84.371 μs | 44.881 μs | 36.091 μs | 351.303 μs | 1.943 ms | 1.146 ms | 84.951 μs |
| add! scalar | Float32 256^3 | 8.457 ms | 7.574 ms | 5.893 ms | 5.483 ms | 3.479 ms | 3.005 ms | 2.740 ms | 2.828 ms | — | 6.480 ms | 1.935 ms | 333.203 μs |
| add! scalar | Float32 512^3 | — | — | — | — | 40.088 ms | 36.698 ms | 36.771 ms | 37.266 ms | — | — | 7.478 ms | — |
| add! scalar | Float32 64^3 | 43.141 μs | 21.824 μs | 10.651 μs | 8.520 μs | 22.110 μs | 12.590 μs | 7.390 μs | 6.550 μs | 85.391 μs | 1.599 ms | 1.040 ms | 55.441 μs |
| add! scalar | Float64 128^3 | 1.551 ms | 1.347 ms | 1.009 ms | 866.257 μs | 321.932 μs | 164.861 μs | 86.151 μs | 72.221 μs | 354.693 μs | 2.024 ms | 1.185 ms | 91.251 μs |
| add! scalar | Float64 256^3 | 17.701 ms | 15.946 ms | 12.391 ms | 11.679 ms | 10.008 ms | 8.937 ms | 8.518 ms | 8.959 ms | — | 5.550 ms | 1.863 ms | 561.766 μs |
| add! scalar | Float64 512^3 | — | — | — | — | 82.856 ms | 73.311 ms | 73.520 ms | 74.742 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 85.390 μs | 49.484 μs | 21.892 μs | 16.987 μs | 40.440 μs | 23.580 μs | 12.010 μs | 9.570 μs | 83.741 μs | 1.494 ms | 1.042 ms | 56.511 μs |
| combine! vec | Float32 128^3 | 2.791 ms | 2.491 ms | 1.937 ms | 1.731 ms | 614.424 μs | 312.393 μs | 156.802 μs | 119.211 μs | — | — | 1.460 ms | 195.792 μs |
| combine! vec | Float32 256^3 | 26.616 ms | 24.004 ms | 18.893 ms | 17.671 ms | 13.777 ms | 13.731 ms | 13.047 ms | 12.925 ms | — | — | 4.150 ms | 1.028 ms |
| combine! vec | Float32 512^3 | — | — | — | — | 110.417 ms | 104.618 ms | 109.830 ms | 110.469 ms | — | — | 19.880 ms | — |
| combine! vec | Float32 64^3 | 129.345 μs | 71.185 μs | 38.072 μs | 19.846 μs | 62.270 μs | 38.220 μs | 19.440 μs | 14.760 μs | — | — | 1.124 ms | 74.601 μs |
| combine! vec | Float64 128^3 | 6.186 ms | 5.637 ms | 4.316 ms | 4.084 ms | 2.139 ms | 1.855 ms | 1.599 ms | 1.490 ms | — | — | 1.695 ms | 245.142 μs |
| combine! vec | Float64 256^3 | 53.020 ms | 48.164 ms | 37.890 ms | 35.457 ms | 28.676 ms | 26.820 ms | 26.890 ms | 27.233 ms | — | — | 4.922 ms | 1.576 ms |
| combine! vec | Float64 512^3 | — | — | — | — | 226.108 ms | 215.025 ms | 217.811 ms | 219.470 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 269.387 μs | 146.932 μs | 80.411 μs | 45.637 μs | 123.191 μs | 63.911 μs | 34.090 μs | 27.020 μs | — | — | 1.119 ms | 68.391 μs |
| cross! | Float32 128^3 | 3.081 ms | 2.621 ms | 2.296 ms | 2.180 ms | 1.931 ms | 995.710 μs | 472.565 μs | 254.163 μs | 1.223 ms | 3.445 ms | 1.087 ms | 138.422 μs |
| cross! | Float32 256^3 | 28.931 ms | 26.586 ms | 24.325 ms | 23.702 ms | 23.986 ms | 17.833 ms | 12.999 ms | 12.846 ms | — | 14.690 ms | 1.775 ms | 832.849 μs |
| cross! | Float32 512^3 | — | — | — | — | 160.298 ms | 110.355 ms | 110.260 ms | 111.126 ms | — | — | 7.558 ms | — |
| cross! | Float32 64^3 | 262.350 μs | 129.860 μs | 72.659 μs | 39.588 μs | 224.361 μs | 117.351 μs | 58.550 μs | 32.850 μs | 219.582 μs | 1.665 ms | 1.031 ms | 57.721 μs |
| cross! | Float64 128^3 | 6.532 ms | 6.049 ms | 5.442 ms | 5.440 ms | 3.727 ms | 2.283 ms | 1.576 ms | 1.472 ms | 1.263 ms | 2.603 ms | 1.367 ms | 257.273 μs |
| cross! | Float64 256^3 | 58.605 ms | 53.033 ms | 49.389 ms | 46.968 ms | 41.930 ms | 29.736 ms | 27.211 ms | 28.050 ms | — | 15.625 ms | 2.733 ms | 1.597 ms |
| cross! | Float64 512^3 | — | — | — | — | 309.185 ms | 220.323 ms | 220.392 ms | 219.403 ms | — | — | — | — |
| cross! | Float64 64^3 | 373.469 μs | 187.020 μs | 101.539 μs | 53.528 μs | 225.192 μs | 116.091 μs | 59.331 μs | 35.440 μs | 216.592 μs | 1.846 ms | 1.103 ms | 66.491 μs |
| det! tensor | Float32 128^3 | 3.660 ms | 2.587 ms | 2.160 ms | 1.966 ms | 2.206 ms | 1.132 ms | 566.697 μs | 286.603 μs | — | — | 1.218 ms | 190.902 μs |
| det! tensor | Float32 256^3 | 36.447 ms | 25.949 ms | 23.192 ms | 21.245 ms | 26.387 ms | 15.076 ms | 12.102 ms | 11.981 ms | — | — | 2.219 ms | 910.320 μs |
| det! tensor | Float32 512^3 | — | — | — | — | 208.671 ms | 123.030 ms | 106.892 ms | 103.119 ms | — | — | 9.408 ms | — |
| det! tensor | Float32 64^3 | 361.565 μs | 186.619 μs | 83.056 μs | 46.689 μs | 251.271 μs | 133.011 μs | 66.371 μs | 35.990 μs | — | — | 966.709 μs | 63.460 μs |
| det! tensor | Float64 128^3 | 6.753 ms | 5.973 ms | 4.837 ms | 4.566 ms | 3.972 ms | 2.419 ms | 1.659 ms | 1.610 ms | — | — | 1.460 ms | 262.872 μs |
| det! tensor | Float64 256^3 | 54.980 ms | 52.857 ms | 43.163 ms | 39.883 ms | 35.635 ms | 25.637 ms | 25.286 ms | 25.978 ms | — | — | 2.941 ms | 1.819 ms |
| det! tensor | Float64 512^3 | — | — | — | — | 359.669 ms | 241.745 ms | 211.334 ms | 207.409 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 363.147 μs | 220.005 μs | 110.514 μs | 60.662 μs | 259.703 μs | 128.941 μs | 74.821 μs | 42.421 μs | — | — | 1.071 ms | 72.640 μs |
| dot! vec.vec | Float32 128^3 | 2.899 ms | 1.731 ms | 1.349 ms | 1.223 ms | 2.455 ms | 1.240 ms | 630.837 μs | 327.414 μs | 538.855 μs | 2.430 ms | 1.239 ms | 117.272 μs |
| dot! vec.vec | Float32 256^3 | 24.982 ms | 18.857 ms | 15.827 ms | 15.018 ms | 25.984 ms | 15.996 ms | 8.960 ms | 8.065 ms | — | 9.651 ms | 2.506 ms | 635.986 μs |
| dot! vec.vec | Float32 512^3 | — | — | — | — | 186.388 ms | 84.610 ms | 73.982 ms | 75.679 ms | — | — | 11.342 ms | — |
| dot! vec.vec | Float32 64^3 | 336.093 μs | 201.695 μs | 106.726 μs | 61.308 μs | 309.091 μs | 159.962 μs | 81.641 μs | 44.521 μs | 112.901 μs | 1.663 ms | 1.107 ms | 59.171 μs |
| dot! vec.vec | Float64 128^3 | 4.596 ms | 3.946 ms | 3.317 ms | 3.108 ms | 3.746 ms | 1.734 ms | 1.035 ms | 576.446 μs | 618.906 μs | 2.505 ms | 1.223 ms | 195.912 μs |
| dot! vec.vec | Float64 256^3 | 44.072 ms | 36.289 ms | 30.450 ms | 28.480 ms | 30.386 ms | 21.632 ms | 17.886 ms | 17.838 ms | — | 9.784 ms | 2.819 ms | 1.231 ms |
| dot! vec.vec | Float64 512^3 | — | — | — | — | 203.567 ms | 150.936 ms | 147.730 ms | 150.136 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 342.485 μs | 207.767 μs | 108.330 μs | 66.523 μs | 318.144 μs | 160.081 μs | 81.551 μs | 44.740 μs | 127.611 μs | 1.656 ms | 1.019 ms | 63.891 μs |
| mul! tensor.vec | Float32 128^3 | 5.241 ms | 4.508 ms | 4.097 ms | 3.891 ms | 3.579 ms | 1.939 ms | 986.251 μs | 770.828 μs | 1.525 ms | 4.295 ms | 1.202 ms | 215.642 μs |
| mul! tensor.vec | Float32 256^3 | 56.838 ms | 41.730 ms | 39.368 ms | 37.470 ms | 42.260 ms | 24.243 ms | 22.927 ms | 21.999 ms | — | 16.892 ms | 2.504 ms | 1.333 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | 339.592 ms | 207.490 ms | 179.508 ms | 172.605 ms | — | — | 12.936 ms | — |
| mul! tensor.vec | Float32 64^3 | 628.537 μs | 242.475 μs | 121.446 μs | 68.588 μs | 372.432 μs | 212.112 μs | 108.061 μs | 57.691 μs | 255.702 μs | 1.882 ms | 1.051 ms | 69.431 μs |
| mul! tensor.vec | Float64 128^3 | 11.484 ms | 10.231 ms | 9.209 ms | 9.025 ms | 6.961 ms | 5.326 ms | 4.307 ms | 4.312 ms | 1.748 ms | 4.757 ms | 1.469 ms | 376.284 μs |
| mul! tensor.vec | Float64 256^3 | 90.503 ms | 85.167 ms | 77.262 ms | 74.028 ms | 62.489 ms | 48.485 ms | 43.790 ms | 43.523 ms | — | 17.818 ms | 3.896 ms | 2.575 ms |
| mul! tensor.vec | Float64 512^3 | — | — | — | — | 538.792 ms | 383.016 ms | 346.830 ms | 339.280 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 695.993 μs | 473.800 μs | 359.566 μs | 211.291 μs | 385.234 μs | 214.322 μs | 109.061 μs | 59.011 μs | 280.183 μs | 1.951 ms | 1.082 ms | 73.421 μs |
| norm! vec | Float32 128^3 | 746.619 μs | 599.150 μs | 478.282 μs | 359.445 μs | 215.871 μs | 116.231 μs | 63.411 μs | 54.230 μs | 411.304 μs | 2.110 ms | 1.077 ms | 90.911 μs |
| norm! vec | Float32 256^3 | 10.798 ms | 10.148 ms | 8.212 ms | 7.831 ms | 5.255 ms | 4.324 ms | 4.109 ms | 4.235 ms | — | 7.304 ms | 2.143 ms | 394.834 μs |
| norm! vec | Float32 512^3 | — | — | — | — | 49.730 ms | 44.163 ms | 45.750 ms | 46.626 ms | — | — | 7.958 ms | — |
| norm! vec | Float32 64^3 | 54.472 μs | 38.606 μs | 20.836 μs | 16.505 μs | 30.810 μs | 19.980 μs | 12.640 μs | 11.230 μs | 100.251 μs | 1.526 ms | 1.029 ms | 54.351 μs |
| norm! vec | Float64 128^3 | 2.313 ms | 2.021 ms | 1.631 ms | 1.458 ms | 454.403 μs | 247.393 μs | 126.042 μs | 103.891 μs | 463.344 μs | 1.434 ms | 1.433 ms | 170.682 μs |
| norm! vec | Float64 256^3 | 22.327 ms | 20.362 ms | 16.905 ms | 15.982 ms | 11.894 ms | 10.319 ms | 10.232 ms | 10.548 ms | — | 9.850 ms | 3.294 ms | 719.807 μs |
| norm! vec | Float64 512^3 | — | — | — | — | 97.959 ms | 91.290 ms | 91.716 ms | 92.730 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 160.911 μs | 91.195 μs | 50.848 μs | 32.368 μs | 56.031 μs | 34.771 μs | 20.640 μs | 16.110 μs | 101.231 μs | 1.681 ms | 1.117 ms | 62.281 μs |
| tr! tensor | Float32 128^3 | 714.866 μs | 548.546 μs | 465.762 μs | 349.269 μs | 214.522 μs | 113.331 μs | 60.451 μs | 50.701 μs | — | — | 1.021 ms | 88.211 μs |
| tr! tensor | Float32 256^3 | 10.668 ms | 9.839 ms | 8.090 ms | 7.701 ms | 4.911 ms | 4.391 ms | 4.259 ms | 4.398 ms | — | — | 1.859 ms | 392.074 μs |
| tr! tensor | Float32 512^3 | — | — | — | — | 47.664 ms | 44.274 ms | 46.374 ms | 46.756 ms | — | — | 8.577 ms | — |
| tr! tensor | Float32 64^3 | 53.777 μs | 34.817 μs | 16.681 μs | 14.213 μs | 27.531 μs | 18.190 μs | 10.810 μs | 9.301 μs | — | — | 1.108 ms | 58.931 μs |
| tr! tensor | Float64 128^3 | 2.278 ms | 1.979 ms | 1.580 ms | 1.405 ms | 448.082 μs | 246.382 μs | 130.051 μs | 98.361 μs | — | — | 1.153 ms | 131.771 μs |
| tr! tensor | Float64 256^3 | 21.191 ms | 19.901 ms | 16.409 ms | 15.480 ms | 11.104 ms | 10.429 ms | 10.460 ms | 10.738 ms | — | — | 2.035 ms | 735.087 μs |
| tr! tensor | Float64 512^3 | — | — | — | — | 97.037 ms | 90.891 ms | 93.008 ms | 93.874 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 107.137 μs | 64.410 μs | 34.513 μs | 22.760 μs | 53.180 μs | 31.230 μs | 18.530 μs | 14.080 μs | — | — | 1.004 ms | 61.020 μs |

## operators

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.644 ms | 2.884 ms | 1.570 ms | 1.284 ms | 3.220 ms | 1.656 ms | 832.119 μs | 427.674 μs | 697.807 μs | 2.544 ms | 1.114 ms | 87.381 μs |
| curl! vec->vec | Float32 256^3 | 47.565 ms | 23.207 ms | 18.167 ms | 17.606 ms | 26.728 ms | 14.003 ms | 8.836 ms | 8.567 ms | — | 10.865 ms | 1.562 ms | 607.226 μs |
| curl! vec->vec | Float32 512^3 | — | — | — | — | 216.314 ms | 122.084 ms | 84.951 ms | 83.542 ms | — | — | 6.384 ms | — |
| curl! vec->vec | Float32 64^3 | 715.869 μs | 361.298 μs | 185.059 μs | 97.663 μs | 415.022 μs | 220.622 μs | 111.302 μs | 60.141 μs | 182.902 μs | 1.646 ms | 1.026 ms | 66.781 μs |
| curl! vec->vec | Float64 128^3 | 5.732 ms | 4.247 ms | 3.988 ms | 3.859 ms | 3.612 ms | 1.877 ms | 942.390 μs | 540.176 μs | 824.588 μs | 3.153 ms | 1.535 ms | 195.982 μs |
| curl! vec->vec | Float64 256^3 | 48.543 ms | 38.387 ms | 36.437 ms | 35.207 ms | 33.383 ms | 22.806 ms | 19.348 ms | 19.480 ms | — | 13.647 ms | 3.147 ms | 1.119 ms |
| curl! vec->vec | Float64 512^3 | — | — | — | — | 243.678 ms | 162.039 ms | 163.494 ms | 165.780 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 685.445 μs | 351.104 μs | 180.555 μs | 96.016 μs | 463.404 μs | 236.962 μs | 119.512 μs | 64.360 μs | 186.242 μs | 1.786 ms | 1.155 ms | 91.521 μs |
| divergence! vec->scalar | Float32 128^3 | 3.583 ms | 1.379 ms | 726.007 μs | 414.664 μs | 3.345 ms | 1.110 ms | 557.726 μs | 290.213 μs | 326.353 μs | 1.957 ms | 1.144 ms | 83.811 μs |
| divergence! vec->scalar | Float32 256^3 | 29.383 ms | 11.815 ms | 9.639 ms | 9.114 ms | 26.547 ms | 8.835 ms | 4.536 ms | 4.149 ms | — | 5.523 ms | 1.734 ms | 409.964 μs |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | 211.843 ms | 69.449 ms | 46.380 ms | 46.696 ms | — | — | 6.985 ms | — |
| divergence! vec->scalar | Float32 64^3 | 427.482 μs | 176.505 μs | 93.067 μs | 51.431 μs | 434.082 μs | 152.522 μs | 78.191 μs | 42.761 μs | 93.900 μs | 1.537 ms | 971.404 μs | 72.011 μs |
| divergence! vec->scalar | Float64 128^3 | 3.927 ms | 2.101 ms | 1.724 ms | 1.552 ms | 3.333 ms | 1.041 ms | 522.976 μs | 276.923 μs | 407.644 μs | 2.306 ms | 1.190 ms | 151.152 μs |
| divergence! vec->scalar | Float64 256^3 | 32.045 ms | 22.048 ms | 17.831 ms | 16.405 ms | 26.943 ms | 11.242 ms | 10.343 ms | 10.268 ms | — | 7.090 ms | 2.578 ms | 751.338 μs |
| divergence! vec->scalar | Float64 512^3 | — | — | — | — | 212.909 ms | 90.905 ms | 91.575 ms | 92.553 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 444.337 μs | 163.080 μs | 87.120 μs | 53.950 μs | 440.124 μs | 142.612 μs | 74.511 μs | 40.900 μs | 103.111 μs | 344.869 μs | 982.625 μs | 67.671 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.411 ms | 1.797 ms | 988.567 μs | 683.645 μs | 3.723 ms | 1.330 ms | 666.358 μs | 349.513 μs | — | — | 1.230 ms | 93.381 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 36.347 ms | 14.813 ms | 12.158 ms | 11.437 ms | 29.563 ms | 10.393 ms | 5.514 ms | 5.483 ms | — | — | 2.109 ms | 493.565 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | — | — | — | — | 236.033 ms | 82.722 ms | 56.207 ms | 56.690 ms | — | — | 7.652 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 539.303 μs | 233.316 μs | 134.678 μs | 71.987 μs | 483.593 μs | 180.972 μs | 94.821 μs | 53.830 μs | — | — | 1.103 ms | 77.531 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.877 ms | 2.753 ms | 2.260 ms | 2.157 ms | 3.588 ms | 1.326 ms | 672.157 μs | 365.563 μs | — | — | 1.365 ms | 193.542 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 39.931 ms | 26.505 ms | 21.953 ms | 20.596 ms | 29.728 ms | 13.847 ms | 12.983 ms | 12.908 ms | — | — | 2.922 ms | 897.899 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | — | — | — | — | 235.050 ms | 113.536 ms | 111.545 ms | 112.568 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 533.393 μs | 216.600 μs | 115.672 μs | 70.444 μs | 476.705 μs | 178.422 μs | 95.051 μs | 52.790 μs | — | — | 1.163 ms | 72.731 μs |
| gradient! scalar->vec | Float32 128^3 | 3.262 ms | 1.702 ms | 880.984 μs | 532.987 μs | 1.948 ms | 970.999 μs | 495.186 μs | 252.183 μs | 560.525 μs | 2.377 ms | 1.076 ms | 81.021 μs |
| gradient! scalar->vec | Float32 256^3 | 26.249 ms | 15.053 ms | 13.785 ms | 13.763 ms | 15.619 ms | 7.853 ms | 5.680 ms | 5.648 ms | — | 7.929 ms | 1.569 ms | 448.944 μs |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | 124.484 ms | 65.576 ms | 63.973 ms | 64.160 ms | — | — | 4.394 ms | — |
| gradient! scalar->vec | Float32 64^3 | 415.585 μs | 221.863 μs | 107.430 μs | 58.414 μs | 247.241 μs | 126.351 μs | 64.151 μs | 35.000 μs | 133.261 μs | 1.681 ms | 1.016 ms | 63.841 μs |
| gradient! scalar->vec | Float64 128^3 | 3.461 ms | 2.907 ms | 2.635 ms | 2.547 ms | 2.082 ms | 981.840 μs | 492.755 μs | 256.823 μs | 605.225 μs | 2.717 ms | 1.313 ms | 174.722 μs |
| gradient! scalar->vec | Float64 256^3 | 32.069 ms | 29.672 ms | 28.081 ms | 27.512 ms | 20.119 ms | 14.821 ms | 15.515 ms | 14.086 ms | — | 10.338 ms | 2.498 ms | 813.838 μs |
| gradient! scalar->vec | Float64 512^3 | — | — | — | — | 154.138 ms | 130.506 ms | 126.931 ms | 128.243 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 368.859 μs | 192.400 μs | 94.043 μs | 56.623 μs | 259.792 μs | 124.621 μs | 64.311 μs | 34.770 μs | 153.172 μs | 1.872 ms | 1.022 ms | 67.491 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.405 ms | 2.303 ms | 1.399 ms | 1.289 ms | 3.444 ms | 1.692 ms | 866.609 μs | 437.904 μs | 1.480 ms | 4.174 ms | 1.196 ms | 91.341 μs |
| helmholtz! vec->vec | Float32 256^3 | 36.655 ms | 19.651 ms | 18.114 ms | 17.670 ms | 28.149 ms | 14.493 ms | 8.546 ms | 8.576 ms | — | 16.637 ms | 1.739 ms | 610.697 μs |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | 217.482 ms | 107.536 ms | 83.066 ms | 83.585 ms | — | — | 6.606 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 558.786 μs | 286.971 μs | 150.825 μs | 78.160 μs | 448.042 μs | 243.912 μs | 116.341 μs | 62.031 μs | 286.333 μs | 1.935 ms | 1.057 ms | 71.270 μs |
| helmholtz! vec->vec | Float64 128^3 | 5.186 ms | 4.220 ms | 3.854 ms | 3.823 ms | 3.824 ms | 1.985 ms | 1.002 ms | 555.776 μs | 1.802 ms | 5.921 ms | 1.598 ms | 250.303 μs |
| helmholtz! vec->vec | Float64 256^3 | 44.813 ms | 38.769 ms | 36.382 ms | 35.180 ms | 34.794 ms | 20.340 ms | 21.392 ms | 20.898 ms | — | 18.240 ms | 3.879 ms | 1.405 ms |
| helmholtz! vec->vec | Float64 512^3 | — | — | — | — | 266.137 ms | 162.904 ms | 163.482 ms | 165.997 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 593.457 μs | 310.953 μs | 156.789 μs | 86.253 μs | 509.185 μs | 265.503 μs | 134.461 μs | 70.791 μs | 342.613 μs | 2.260 ms | 1.218 ms | 92.031 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 6.146 ms | 3.063 ms | 1.840 ms | 1.618 ms | 4.173 ms | 2.090 ms | 1.055 ms | 533.866 μs | — | — | 1.065 ms | 125.682 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 50.158 ms | 24.608 ms | 20.555 ms | 19.673 ms | 33.972 ms | 17.378 ms | 9.863 ms | 9.900 ms | — | — | 1.706 ms | 688.697 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | — | — | — | — | 265.395 ms | 133.253 ms | 92.150 ms | 92.251 ms | — | — | 7.390 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 779.149 μs | 395.970 μs | 200.974 μs | 106.172 μs | 557.203 μs | 284.383 μs | 143.132 μs | 77.271 μs | — | — | 1.107 ms | 76.791 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 6.666 ms | 4.845 ms | 4.468 ms | 4.407 ms | 4.672 ms | 2.395 ms | 1.202 ms | 762.748 μs | — | — | 1.683 ms | 294.383 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 56.105 ms | 43.079 ms | 40.773 ms | 39.444 ms | 41.058 ms | 22.698 ms | 21.886 ms | 21.926 ms | — | — | 4.462 ms | 1.752 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | — | — | — | — | 341.644 ms | 187.690 ms | 182.742 ms | 183.863 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 817.503 μs | 417.490 μs | 213.933 μs | 113.394 μs | 630.046 μs | 326.973 μs | 166.362 μs | 88.231 μs | — | — | 964.417 μs | 98.912 μs |
| laplacian! scalar | Float32 128^3 | 2.064 ms | 654.294 μs | 335.668 μs | 174.654 μs | 2.144 ms | 496.465 μs | 249.722 μs | 129.841 μs | 265.103 μs | 1.910 ms | 1.181 ms | 73.201 μs |
| laplacian! scalar | Float32 256^3 | 17.204 ms | 6.266 ms | 5.114 ms | 4.573 ms | 17.069 ms | 3.870 ms | 1.954 ms | 1.193 ms | — | 5.490 ms | 1.688 ms | 256.932 μs |
| laplacian! scalar | Float32 512^3 | — | — | — | — | 136.607 ms | 31.534 ms | 27.349 ms | 26.377 ms | — | — | 5.262 ms | — |
| laplacian! scalar | Float32 64^3 | 253.409 μs | 90.201 μs | 49.778 μs | 29.951 μs | 274.481 μs | 68.050 μs | 36.190 μs | 22.171 μs | 83.431 μs | 1.563 ms | 957.239 μs | 55.721 μs |
| laplacian! scalar | Float64 128^3 | 2.151 ms | 818.689 μs | 625.527 μs | 453.410 μs | 2.224 ms | 526.685 μs | 266.453 μs | 140.211 μs | 278.082 μs | 1.957 ms | 1.174 ms | 100.031 μs |
| laplacian! scalar | Float64 256^3 | 17.670 ms | 12.629 ms | 11.985 ms | 11.511 ms | 17.706 ms | 5.193 ms | 4.767 ms | 4.856 ms | — | 4.740 ms | 1.795 ms | 422.524 μs |
| laplacian! scalar | Float64 512^3 | — | — | — | — | 141.089 ms | 54.622 ms | 54.800 ms | 54.912 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 258.431 μs | 94.484 μs | 52.006 μs | 32.627 μs | 282.683 μs | 72.701 μs | 38.870 μs | 23.750 μs | 84.420 μs | 1.586 ms | 1.058 ms | 67.900 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.568 ms | 6.270 ms | 4.679 ms | 4.632 ms | 9.579 ms | 4.883 ms | 2.435 ms | 1.245 ms | — | — | 1.173 ms | 222.682 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 95.270 ms | 51.396 ms | 45.242 ms | 43.393 ms | 78.926 ms | 43.080 ms | 25.131 ms | 24.144 ms | — | — | 2.615 ms | 1.217 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | — | — | — | — | 650.794 ms | 348.570 ms | 208.897 ms | 198.191 ms | — | — | 14.783 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.541 ms | 759.204 μs | 384.861 μs | 200.176 μs | 1.219 ms | 619.876 μs | 311.424 μs | 159.142 μs | — | — | 1.040 ms | 83.131 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 14.266 ms | 11.445 ms | 10.440 ms | 10.391 ms | 10.502 ms | 5.708 ms | 3.773 ms | 3.750 ms | — | — | 1.627 ms | 365.333 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 116.759 ms | 95.790 ms | 88.096 ms | 86.966 ms | 85.247 ms | 58.565 ms | 48.361 ms | 53.237 ms | — | — | 4.370 ms | 2.300 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | — | — | — | — | 707.622 ms | 436.041 ms | 391.600 ms | 392.482 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.606 ms | 785.084 μs | 414.935 μs | 219.733 μs | 1.273 ms | 645.546 μs | 324.904 μs | 166.521 μs | — | — | 1.192 ms | 96.701 μs |

## convolution

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.848 ms | 519.172 μs | 460.198 μs | 358.481 μs | 1.363 ms | 302.643 μs | 154.672 μs | 84.481 μs | 296.642 μs | 1.855 ms | 991.293 μs | 132.441 μs |
| assignment_window | Float32 256^3 | 27.534 ms | 4.133 ms | 5.588 ms | 3.470 ms | 18.192 ms | 2.407 ms | 3.964 ms | 2.582 ms | — | 3.952 ms | 1.684 ms | 265.273 μs |
| assignment_window | Float32 512^3 | — | — | — | — | 150.273 ms | 54.646 ms | 32.646 ms | 21.714 ms | — | — | 5.043 ms | — |
| assignment_window | Float32 64^3 | 240.424 μs | 65.194 μs | 44.367 μs | 38.678 μs | 176.171 μs | 44.551 μs | 25.010 μs | 16.820 μs | 138.651 μs | 1.640 ms | 1.027 ms | 146.232 μs |
| assignment_window | Float64 128^3 | 1.901 ms | 1.011 ms | 820.985 μs | 575.925 μs | 1.547 ms | 391.964 μs | 341.664 μs | 302.533 μs | 306.863 μs | 1.901 ms | 1.136 ms | 136.972 μs |
| assignment_window | Float64 256^3 | 41.039 ms | 8.489 ms | 9.793 ms | 6.226 ms | 28.203 ms | 11.692 ms | 7.469 ms | 4.911 ms | — | 4.237 ms | 1.784 ms | 308.553 μs |
| assignment_window | Float64 512^3 | — | — | — | — | 219.788 ms | 91.854 ms | 60.258 ms | 43.437 ms | — | — | — | — |
| assignment_window | Float64 64^3 | 237.586 μs | 68.329 μs | 65.607 μs | 64.938 μs | 198.512 μs | 47.141 μs | 26.580 μs | 17.800 μs | 141.232 μs | 1.542 ms | 1.162 ms | 120.351 μs |
| combine!∘kernel vector | Float32 128^3 | 4.099 ms | 2.240 ms | 1.715 ms | 1.645 ms | 3.149 ms | 1.548 ms | 775.438 μs | 415.504 μs | — | — | 957.518 μs | 135.642 μs |
| combine!∘kernel vector | Float32 256^3 | 37.490 ms | 22.146 ms | 20.259 ms | 19.790 ms | 26.122 ms | 13.735 ms | 9.876 ms | 9.919 ms | — | — | 1.958 ms | 926.920 μs |
| combine!∘kernel vector | Float32 512^3 | — | — | — | — | 236.954 ms | 107.806 ms | 92.026 ms | 92.874 ms | — | — | 8.534 ms | — |
| combine!∘kernel vector | Float32 64^3 | 494.715 μs | 267.940 μs | 134.409 μs | 75.209 μs | 424.303 μs | 206.562 μs | 105.272 μs | 55.441 μs | — | — | 1.101 ms | 73.460 μs |
| combine!∘kernel vector | Float64 128^3 | 5.648 ms | 4.900 ms | 4.435 ms | 4.427 ms | 3.711 ms | 2.038 ms | 1.081 ms | 751.208 μs | — | — | 1.469 ms | 308.753 μs |
| combine!∘kernel vector | Float64 256^3 | 50.199 ms | 44.417 ms | 40.732 ms | 40.012 ms | 33.586 ms | 23.103 ms | 21.937 ms | 23.325 ms | — | — | 3.008 ms | 1.792 ms |
| combine!∘kernel vector | Float64 512^3 | — | — | — | — | 245.574 ms | 186.440 ms | 184.816 ms | 184.166 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 516.288 μs | 283.545 μs | 142.485 μs | 81.472 μs | 384.824 μs | 229.923 μs | 119.052 μs | 63.020 μs | — | — | 1.001 ms | 84.851 μs |
| convolve! scalar | Float32 128^3 | 1.622 ms | 314.111 μs | 205.492 μs | 87.696 μs | 924.667 μs | 103.361 μs | 53.851 μs | 36.901 μs | 220.032 μs | 1.755 ms | 877.910 μs | 67.921 μs |
| convolve! scalar | Float32 256^3 | 13.663 ms | 8.198 ms | 7.751 ms | 7.123 ms | 7.608 ms | 2.859 ms | 2.670 ms | 2.722 ms | — | 3.659 ms | 1.656 ms | 312.313 μs |
| convolve! scalar | Float32 512^3 | — | — | — | — | 62.045 ms | 37.063 ms | 36.563 ms | 37.142 ms | — | — | 4.192 ms | — |
| convolve! scalar | Float32 64^3 | 202.015 μs | 26.689 μs | 14.629 μs | 11.683 μs | 117.031 μs | 16.010 μs | 9.540 μs | 7.553 μs | 78.951 μs | 1.480 ms | 1.035 ms | 49.221 μs |
| convolve! scalar | Float64 128^3 | 1.847 ms | 1.390 ms | 1.185 ms | 1.117 ms | 1.011 ms | 168.442 μs | 91.551 μs | 71.711 μs | 302.553 μs | 1.784 ms | 1.135 ms | 88.360 μs |
| convolve! scalar | Float64 256^3 | 19.136 ms | 16.911 ms | 16.014 ms | 15.178 ms | 10.939 ms | 7.865 ms | 7.608 ms | 7.751 ms | — | 4.442 ms | 2.019 ms | 561.696 μs |
| convolve! scalar | Float64 512^3 | — | — | — | — | 89.873 ms | 73.853 ms | 73.800 ms | 74.177 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 181.121 μs | 55.189 μs | 26.100 μs | 18.116 μs | 125.971 μs | 25.231 μs | 13.890 μs | 10.570 μs | 78.591 μs | 1.618 ms | 951.395 μs | 60.310 μs |
| convolve! vector | Float32 128^3 | 2.765 ms | 1.925 ms | 1.659 ms | 1.593 ms | 2.096 ms | 1.103 ms | 548.776 μs | 294.353 μs | 731.727 μs | 2.557 ms | 921.484 μs | 131.011 μs |
| convolve! vector | Float32 256^3 | 26.736 ms | 21.677 ms | 20.002 ms | 19.668 ms | 19.875 ms | 11.041 ms | 9.827 ms | 9.903 ms | — | 10.821 ms | 1.185 ms | 677.477 μs |
| convolve! vector | Float32 512^3 | — | — | — | — | 173.623 ms | 93.462 ms | 91.827 ms | 92.722 ms | — | — | 6.065 ms | — |
| convolve! vector | Float32 64^3 | 318.386 μs | 178.979 μs | 90.308 μs | 49.964 μs | 273.421 μs | 146.812 μs | 74.521 μs | 40.310 μs | 161.751 μs | 1.595 ms | 1.094 ms | 65.831 μs |
| convolve! vector | Float64 128^3 | 5.261 ms | 4.843 ms | 4.388 ms | 4.243 ms | 2.641 ms | 1.529 ms | 861.970 μs | 750.527 μs | 792.657 μs | 2.910 ms | 1.329 ms | 233.663 μs |
| convolve! vector | Float64 256^3 | 46.440 ms | 43.366 ms | 40.450 ms | 39.756 ms | 30.415 ms | 22.854 ms | 21.933 ms | 23.331 ms | — | 12.297 ms | 2.365 ms | 1.289 ms |
| convolve! vector | Float64 512^3 | — | — | — | — | 212.834 ms | 185.094 ms | 184.676 ms | 184.058 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 284.305 μs | 169.910 μs | 89.571 μs | 54.907 μs | 223.112 μs | 135.422 μs | 74.021 μs | 39.880 μs | 167.451 μs | 1.655 ms | 1.102 ms | 76.490 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.737 ms | 2.434 ms | 1.659 ms | 900.167 μs | 5.009 ms | 2.116 ms | 1.063 ms | 544.335 μs | — | — | 1.058 ms | 80.111 μs |
| exponential_convolve! scalar | Float32 256^3 | 34.376 ms | 13.310 ms | 7.294 ms | 5.716 ms | 39.552 ms | 16.720 ms | 8.368 ms | 4.319 ms | — | — | 1.651 ms | 252.972 μs |
| exponential_convolve! scalar | Float32 512^3 | — | — | — | — | 316.060 ms | 135.381 ms | 66.866 ms | 35.092 ms | — | — | 5.951 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 2.197 ms | 1.065 ms | 569.902 μs | 299.039 μs | 643.393 μs | 280.313 μs | 144.572 μs | 79.221 μs | — | — | 999.111 μs | 54.120 μs |
| exponential_convolve! scalar | Float64 128^3 | 8.249 ms | 3.745 ms | 2.332 ms | 1.452 ms | 5.640 ms | 2.373 ms | 1.196 ms | 619.856 μs | — | — | 1.328 ms | 132.001 μs |
| exponential_convolve! scalar | Float64 256^3 | 55.341 ms | 24.571 ms | 14.316 ms | 11.623 ms | 44.638 ms | 18.856 ms | 9.478 ms | 5.019 ms | — | — | 2.622 ms | 634.206 μs |
| exponential_convolve! scalar | Float64 512^3 | — | — | — | — | 356.291 ms | 150.159 ms | 75.089 ms | 55.114 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 728.857 μs | 327.894 μs | 171.385 μs | 96.734 μs | 710.637 μs | 316.063 μs | 160.722 μs | 85.891 μs | — | — | 986.434 μs | 63.140 μs |
| exponential_convolve! vector | Float32 128^3 | 19.222 ms | 9.091 ms | 5.798 ms | 3.138 ms | 16.929 ms | 7.645 ms | 3.833 ms | 1.952 ms | — | — | 1.208 ms | 172.062 μs |
| exponential_convolve! vector | Float32 256^3 | 116.910 ms | 53.126 ms | 28.672 ms | 18.878 ms | 134.225 ms | 60.514 ms | 30.335 ms | 15.801 ms | — | — | 3.202 ms | 696.697 μs |
| exponential_convolve! vector | Float32 512^3 | — | — | — | — | 1.081 s | 493.354 ms | 248.483 ms | 126.340 ms | — | — | 14.658 ms | — |
| exponential_convolve! vector | Float32 64^3 | 6.916 ms | 3.524 ms | 1.824 ms | 944.164 μs | 2.177 ms | 990.440 μs | 500.095 μs | 262.122 μs | — | — | 1.051 ms | 66.501 μs |
| exponential_convolve! vector | Float64 128^3 | 27.270 ms | 12.988 ms | 7.841 ms | 5.008 ms | 18.460 ms | 8.592 ms | 4.469 ms | 2.188 ms | — | — | 1.842 ms | 284.593 μs |
| exponential_convolve! vector | Float64 256^3 | 184.797 ms | 87.239 ms | 47.961 ms | 35.237 ms | 148.574 ms | 67.989 ms | 34.155 ms | 19.364 ms | — | — | 5.713 ms | 1.737 ms |
| exponential_convolve! vector | Float64 512^3 | — | — | — | — | 1.203 s | 541.601 ms | 271.739 ms | 165.041 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.524 ms | 1.171 ms | 604.600 μs | 321.396 μs | 2.373 ms | 1.100 ms | 552.056 μs | 285.293 μs | — | — | 1.060 ms | 87.581 μs |
| spectral_band | Float32 128^3 | 4.252 ms | 1.621 ms | 834.592 μs | 441.121 μs | 3.861 ms | 1.363 ms | 686.498 μs | 350.174 μs | 334.154 μs | 2.050 ms | 1.005 ms | 99.451 μs |
| spectral_band | Float32 256^3 | 46.117 ms | 12.797 ms | 10.084 ms | 5.548 ms | 39.028 ms | 10.837 ms | 8.116 ms | 4.148 ms | — | 6.344 ms | 1.755 ms | 276.693 μs |
| spectral_band | Float32 512^3 | — | — | — | — | 313.727 ms | 125.402 ms | 63.690 ms | 32.797 ms | — | — | 7.315 ms | — |
| spectral_band | Float32 64^3 | 540.920 μs | 216.585 μs | 115.386 μs | 63.530 μs | 491.882 μs | 179.942 μs | 92.401 μs | 50.071 μs | 106.071 μs | 1.537 ms | 1.000 ms | 81.691 μs |
| spectral_band | Float64 128^3 | 4.310 ms | 1.590 ms | 966.909 μs | 624.952 μs | 3.972 ms | 1.379 ms | 700.328 μs | 358.724 μs | 361.113 μs | 2.105 ms | 1.221 ms | 111.781 μs |
| spectral_band | Float64 256^3 | 58.860 ms | 12.495 ms | 13.852 ms | 8.086 ms | 48.199 ms | 19.618 ms | 10.397 ms | 5.681 ms | — | 5.611 ms | 2.014 ms | 308.103 μs |
| spectral_band | Float64 512^3 | — | — | — | — | 387.716 ms | 154.477 ms | 81.669 ms | 44.926 ms | — | — | — | — |
| spectral_band | Float64 64^3 | 530.525 μs | 214.887 μs | 113.729 μs | 71.733 μs | 504.425 μs | 181.782 μs | 94.061 μs | 50.371 μs | 110.411 μs | 1.651 ms | 866.015 μs | 76.821 μs |
| spectral_cutoff | Float32 128^3 | 4.270 ms | 1.655 ms | 839.296 μs | 442.373 μs | 3.861 ms | 1.365 ms | 685.638 μs | 349.054 μs | 331.623 μs | 2.046 ms | 1.093 ms | 96.771 μs |
| spectral_cutoff | Float32 256^3 | 45.919 ms | 12.710 ms | 10.131 ms | 5.435 ms | 38.978 ms | 10.802 ms | 8.038 ms | 4.147 ms | — | 5.403 ms | 1.983 ms | 273.973 μs |
| spectral_cutoff | Float32 512^3 | — | — | — | — | 311.850 ms | 125.266 ms | 64.900 ms | 32.890 ms | — | — | 6.140 ms | — |
| spectral_cutoff | Float32 64^3 | 548.228 μs | 217.012 μs | 114.396 μs | 63.484 μs | 491.113 μs | 180.422 μs | 92.221 μs | 50.111 μs | 108.881 μs | 1.625 ms | 1.105 ms | 78.001 μs |
| spectral_cutoff | Float64 128^3 | 4.261 ms | 1.590 ms | 972.055 μs | 631.094 μs | 3.974 ms | 1.376 ms | 692.888 μs | 361.054 μs | 351.793 μs | 2.120 ms | 1.131 ms | 111.871 μs |
| spectral_cutoff | Float64 256^3 | 59.017 ms | 12.879 ms | 13.948 ms | 8.048 ms | 47.916 ms | 19.593 ms | 10.329 ms | 5.687 ms | — | 5.621 ms | 2.006 ms | 297.583 μs |
| spectral_cutoff | Float64 512^3 | — | — | — | — | 385.679 ms | 154.347 ms | 81.265 ms | 45.121 ms | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 534.876 μs | 213.217 μs | 114.093 μs | 69.801 μs | 505.075 μs | 181.882 μs | 93.861 μs | 50.351 μs | 117.711 μs | 1.647 ms | 1.006 ms | 79.521 μs |
| squared_wavenumber_field | Float32 128^3 | 1.881 ms | 489.911 μs | 448.601 μs | 349.437 μs | 1.374 ms | 296.773 μs | 151.562 μs | 80.491 μs | 262.463 μs | 1.824 ms | 961.813 μs | 89.241 μs |
| squared_wavenumber_field | Float32 256^3 | 27.592 ms | 4.127 ms | 5.585 ms | 3.472 ms | 18.523 ms | 2.407 ms | 3.952 ms | 2.650 ms | — | 3.812 ms | 1.541 ms | 217.462 μs |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | 153.841 ms | 55.384 ms | 32.029 ms | 21.845 ms | — | — | 4.991 ms | — |
| squared_wavenumber_field | Float32 64^3 | 233.436 μs | 63.047 μs | 35.087 μs | 39.058 μs | 176.371 μs | 42.000 μs | 22.581 μs | 14.110 μs | 91.321 μs | 1.517 ms | 954.784 μs | 75.471 μs |
| squared_wavenumber_field | Float64 128^3 | 1.904 ms | 1.001 ms | 818.893 μs | 591.955 μs | 1.420 ms | 400.024 μs | 312.834 μs | 313.023 μs | 264.163 μs | 1.805 ms | 1.079 ms | 85.741 μs |
| squared_wavenumber_field | Float64 256^3 | 41.025 ms | 8.109 ms | 9.821 ms | 6.080 ms | 27.815 ms | 11.584 ms | 7.241 ms | 5.243 ms | — | 4.151 ms | 1.758 ms | 242.943 μs |
| squared_wavenumber_field | Float64 512^3 | — | — | — | — | 216.394 ms | 90.064 ms | 59.506 ms | 43.335 ms | — | — | — | — |
| squared_wavenumber_field | Float64 64^3 | 235.679 μs | 63.357 μs | 67.986 μs | 62.943 μs | 181.941 μs | 42.580 μs | 22.780 μs | 14.301 μs | 88.931 μs | 1.612 ms | 1.059 ms | 71.531 μs |
| translation_kernel | Float32 128^3 | 1.839 ms | 787.619 μs | 481.587 μs | 331.665 μs | 1.535 ms | 447.215 μs | 229.213 μs | 119.671 μs | — | — | 1.218 ms | 119.851 μs |
| translation_kernel | Float32 256^3 | 27.554 ms | 6.188 ms | 6.949 ms | 4.066 ms | 19.644 ms | 3.546 ms | 4.326 ms | 2.736 ms | — | — | 1.653 ms | 253.023 μs |
| translation_kernel | Float32 512^3 | — | — | — | — | 163.420 ms | 66.037 ms | 35.181 ms | 22.985 ms | — | — | 5.084 ms | — |
| translation_kernel | Float32 64^3 | 232.583 μs | 105.855 μs | 58.738 μs | 40.614 μs | 196.951 μs | 60.760 μs | 32.420 μs | 20.000 μs | — | — | 1.138 ms | 111.791 μs |
| translation_kernel | Float64 128^3 | 1.827 ms | 1.003 ms | 769.033 μs | 536.206 μs | 1.448 ms | 458.384 μs | 300.773 μs | 313.273 μs | — | — | 1.338 ms | 146.652 μs |
| translation_kernel | Float64 256^3 | 41.093 ms | 8.494 ms | 10.708 ms | 6.716 ms | 27.323 ms | 13.179 ms | 7.617 ms | 5.310 ms | — | — | 2.213 ms | 446.935 μs |
| translation_kernel | Float64 512^3 | — | — | — | — | 217.288 ms | 103.991 ms | 62.348 ms | 43.070 ms | — | — | — | — |
| translation_kernel | Float64 64^3 | 231.216 μs | 101.023 μs | 74.401 μs | 60.787 μs | 187.282 μs | 62.820 μs | 33.361 μs | 20.790 μs | — | — | 1.188 ms | 103.861 μs |

## transfer

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 28.888 ms | 13.922 ms | 7.765 ms | 4.633 ms | 20.758 ms | 11.019 ms | 5.949 ms | 3.429 ms | 2.280 ms | 4.864 ms | 1.343 ms | 198.222 μs |
| anterpolate! CatmullRom | Float32 256^3 | 436.132 ms | 225.143 ms | 120.356 ms | 75.195 ms | 171.279 ms | 88.660 ms | 45.749 ms | 23.942 ms | — | 17.932 ms | 4.044 ms | 2.900 ms |
| anterpolate! CatmullRom | Float32 512^3 | — | — | — | — | 2.901 s | 1.472 s | 779.357 ms | 433.699 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.238 ms | 1.913 ms | 1.248 ms | 938.078 μs | 2.515 ms | 1.448 ms | 929.910 μs | 652.486 μs | 116.972 μs | 2.057 ms | 1.220 ms | 125.551 μs |
| anterpolate! CatmullRom | Float64 128^3 | 34.657 ms | 16.258 ms | 8.125 ms | 4.852 ms | 21.771 ms | 11.463 ms | 6.141 ms | 3.529 ms | 2.691 ms | 4.862 ms | 1.628 ms | 229.902 μs |
| anterpolate! CatmullRom | Float64 256^3 | 546.414 ms | 287.805 ms | 165.743 ms | 114.407 ms | 262.715 ms | 134.730 ms | 67.933 ms | 35.634 ms | — | 19.810 ms | 4.795 ms | 4.675 ms |
| anterpolate! CatmullRom | Float64 512^3 | — | — | — | — | 3.274 s | 1.701 s | 898.583 ms | 523.480 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.389 ms | 1.879 ms | 1.262 ms | 943.395 μs | 2.530 ms | 1.504 ms | 964.291 μs | 696.417 μs | 185.312 μs | 2.004 ms | 1.201 ms | 120.692 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 206.898 ms | 102.438 ms | 54.108 ms | 29.977 ms | 159.941 ms | 80.592 ms | 40.618 ms | 21.724 ms | 12.241 ms | 15.478 ms | 4.182 ms | 1.001 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.398 s | 1.309 s | 748.243 ms | 530.262 ms | 1.282 s | 644.026 ms | 323.089 ms | 162.262 ms | — | 48.567 ms | 18.203 ms | 14.971 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 11.711 s | 5.931 s | 3.037 s | 1.632 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.505 ms | 13.324 ms | 8.405 ms | 5.731 ms | 19.875 ms | 10.618 ms | 6.448 ms | 4.342 ms | 486.825 μs | 5.959 ms | 2.191 ms | 333.264 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 229.887 ms | 111.011 ms | 56.260 ms | 31.446 ms | 160.435 ms | 80.897 ms | 40.579 ms | 21.610 ms | 13.808 ms | 16.564 ms | 4.883 ms | 1.186 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.816 s | 1.516 s | 925.966 ms | 682.498 ms | 1.405 s | 740.021 ms | 354.937 ms | 179.837 ms | — | 66.043 ms | 28.833 ms | 24.253 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 12.684 s | 7.446 s | 3.362 s | 2.122 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 25.148 ms | 13.373 ms | 8.536 ms | 5.942 ms | 19.923 ms | 10.890 ms | 6.559 ms | 4.422 ms | 825.268 μs | 5.503 ms | 2.720 ms | 326.584 μs |
| anterpolate! NUFFT | Float32 128^3 | 440.339 ms | 240.566 ms | 162.121 ms | 126.581 ms | 368.615 ms | 196.797 ms | 111.515 ms | 53.040 ms | 20.177 ms | 18.762 ms | 5.604 ms | 2.767 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.637 s | 2.564 s | 1.595 s | 1.215 s | 3.755 s | 1.987 s | 1.113 s | 687.461 ms | — | 120.799 ms | 32.967 ms | 28.423 ms |
| anterpolate! NUFFT | Float32 512^3 | — | — | — | — | 31.064 s | 16.350 s | 9.030 s | 5.484 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 33.293 ms | 18.266 ms | 11.751 ms | 8.822 ms | 26.991 ms | 14.206 ms | 8.895 ms | 5.920 ms | 1.989 ms | 6.296 ms | 2.380 ms | 457.115 μs |
| anterpolate! NUFFT | Float64 128^3 | 581.682 ms | 329.204 ms | 231.408 ms | 191.318 ms | 421.561 ms | 237.582 ms | 144.828 ms | 103.084 ms | 30.358 ms | 22.503 ms | 10.016 ms | 6.549 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.457 s | 3.104 s | 2.052 s | 1.678 s | 3.613 s | 2.024 s | 1.227 s | 873.785 ms | — | 160.735 ms | 70.065 ms | 58.071 ms |
| anterpolate! NUFFT | Float64 512^3 | — | — | — | — | 39.632 s | 21.769 s | 12.660 s | 8.234 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 40.161 ms | 22.518 ms | 15.032 ms | 11.464 ms | 32.999 ms | 17.931 ms | 10.798 ms | 6.956 ms | 3.892 ms | 8.203 ms | 3.612 ms | 830.519 μs |
| anterpolate! trilinear | Float32 128^3 | 4.520 ms | 2.277 ms | 1.400 ms | 963.981 μs | 4.543 ms | 2.526 ms | 1.412 ms | 854.799 μs | 460.884 μs | 2.018 ms | 990.949 μs | 80.131 μs |
| anterpolate! trilinear | Float32 256^3 | 89.673 ms | 48.898 ms | 28.408 ms | 21.164 ms | 40.404 ms | 22.154 ms | 11.815 ms | 6.645 ms | — | 6.631 ms | 1.780 ms | 724.118 μs |
| anterpolate! trilinear | Float32 512^3 | — | — | — | — | 732.091 ms | 378.550 ms | 205.903 ms | 115.419 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 491.280 μs | 331.491 μs | 225.859 μs | 179.253 μs | 369.902 μs | 228.553 μs | 168.402 μs | 126.121 μs | 70.080 μs | 1.565 ms | 1.061 ms | 71.821 μs |
| anterpolate! trilinear | Float64 128^3 | 5.640 ms | 2.855 ms | 1.720 ms | 1.321 ms | 5.772 ms | 3.256 ms | 1.871 ms | 1.143 ms | 596.666 μs | 1.980 ms | 1.202 ms | 101.491 μs |
| anterpolate! trilinear | Float64 256^3 | 97.343 ms | 55.716 ms | 36.209 ms | 29.492 ms | 72.461 ms | 37.716 ms | 20.072 ms | 11.191 ms | — | 6.838 ms | 1.761 ms | 1.126 ms |
| anterpolate! trilinear | Float64 512^3 | — | — | — | — | 762.357 ms | 412.729 ms | 214.310 ms | 127.474 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 523.595 μs | 343.748 μs | 259.583 μs | 210.906 μs | 379.254 μs | 239.993 μs | 175.862 μs | 134.162 μs | 83.721 μs | 1.554 ms | 936.908 μs | 90.761 μs |
| interpolate! CatmullRom | Float32 128^3 | 12.564 ms | 6.150 ms | 3.087 ms | 1.711 ms | 5.462 ms | 2.772 ms | 1.393 ms | 738.557 μs | 972.889 μs | 3.140 ms | 1.376 ms | 125.191 μs |
| interpolate! CatmullRom | Float32 256^3 | 298.273 ms | 156.282 ms | 82.104 ms | 53.577 ms | 45.860 ms | 28.003 ms | 14.403 ms | 7.560 ms | — | 14.577 ms | 2.785 ms | 868.109 μs |
| interpolate! CatmullRom | Float32 512^3 | — | — | — | — | 1.807 s | 893.835 ms | 468.550 ms | 257.683 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.333 ms | 715.329 μs | 437.043 μs | 299.843 μs | 614.913 μs | 331.863 μs | 200.702 μs | 134.681 μs | 101.321 μs | 1.724 ms | 1.188 ms | 85.831 μs |
| interpolate! CatmullRom | Float64 128^3 | 17.215 ms | 7.511 ms | 3.790 ms | 1.989 ms | 5.637 ms | 2.906 ms | 1.443 ms | 801.029 μs | 1.411 ms | 2.789 ms | 1.410 ms | 197.732 μs |
| interpolate! CatmullRom | Float64 256^3 | 326.167 ms | 167.984 ms | 98.558 ms | 65.427 ms | 155.856 ms | 77.712 ms | 38.058 ms | 19.242 ms | — | 12.939 ms | 2.854 ms | 1.728 ms |
| interpolate! CatmullRom | Float64 512^3 | — | — | — | — | 1.976 s | 1.037 s | 539.426 ms | 303.341 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.418 ms | 755.274 μs | 460.251 μs | 320.814 μs | 671.996 μs | 356.764 μs | 214.333 μs | 145.302 μs | 166.201 μs | 1.759 ms | 1.283 ms | 117.071 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 77.824 ms | 39.254 ms | 19.789 ms | 10.830 ms | 42.448 ms | 21.323 ms | 10.677 ms | 5.643 ms | 5.370 ms | 14.027 ms | 3.038 ms | 472.455 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.545 s | 885.882 ms | 541.871 ms | 353.399 ms | 333.170 ms | 187.215 ms | 94.495 ms | 47.768 ms | — | 30.216 ms | 11.603 ms | 4.732 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 5.375 s | 2.819 s | 1.507 s | 868.799 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.922 ms | 4.742 ms | 2.891 ms | 1.939 ms | 5.066 ms | 2.680 ms | 1.606 ms | 1.080 ms | 688.416 μs | 3.166 ms | 1.783 ms | 277.603 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 99.290 ms | 48.176 ms | 24.054 ms | 13.184 ms | 41.832 ms | 21.240 ms | 11.325 ms | 5.550 ms | 8.105 ms | 9.517 ms | 2.980 ms | 839.199 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.989 s | 1.100 s | 707.401 ms | 470.630 ms | 624.172 ms | 314.413 ms | 149.140 ms | 76.081 ms | — | 28.103 ms | 10.932 ms | 10.040 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 6.901 s | 3.680 s | 1.824 s | 1.169 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.195 ms | 4.828 ms | 2.989 ms | 2.017 ms | 5.260 ms | 2.792 ms | 1.670 ms | 1.118 ms | 911.428 μs | 3.595 ms | 2.314 ms | 340.124 μs |
| interpolate! NUFFT | Float32 128^3 | 343.312 ms | 196.862 ms | 143.368 ms | 99.919 ms | 244.375 ms | 140.993 ms | 84.093 ms | 44.971 ms | 12.723 ms | 16.422 ms | 4.893 ms | 1.913 ms |
| interpolate! NUFFT | Float32 256^3 | 3.806 s | 2.221 s | 1.451 s | 1.054 s | 2.974 s | 1.608 s | 932.447 ms | 604.339 ms | — | 72.243 ms | 26.214 ms | 17.680 ms |
| interpolate! NUFFT | Float32 512^3 | — | — | — | — | 24.841 s | 13.216 s | 7.622 s | 4.947 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 17.897 ms | 10.623 ms | 7.107 ms | 5.480 ms | 11.906 ms | 6.287 ms | 3.778 ms | 2.420 ms | 1.847 ms | 4.302 ms | 2.275 ms | 449.465 μs |
| interpolate! NUFFT | Float64 128^3 | 456.351 ms | 275.340 ms | 209.942 ms | 177.430 ms | 215.977 ms | 137.454 ms | 94.701 ms | 76.130 ms | 25.361 ms | 18.237 ms | 8.627 ms | 5.536 ms |
| interpolate! NUFFT | Float64 256^3 | 4.178 s | 2.527 s | 1.822 s | 1.457 s | 1.976 s | 1.206 s | 854.817 ms | 716.526 ms | — | 118.516 ms | 56.632 ms | 47.601 ms |
| interpolate! NUFFT | Float64 512^3 | — | — | — | — | 24.809 s | 13.975 s | 8.780 s | 9.436 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 24.681 ms | 15.168 ms | 11.037 ms | 9.321 ms | 17.531 ms | 9.868 ms | 6.127 ms | 3.951 ms | 3.417 ms | 6.116 ms | 3.003 ms | 937.640 μs |
| interpolate! trilinear | Float32 128^3 | 2.040 ms | 1.064 ms | 548.762 μs | 298.410 μs | 1.313 ms | 685.317 μs | 339.743 μs | 180.192 μs | 255.582 μs | 1.719 ms | 1.094 ms | 68.090 μs |
| interpolate! trilinear | Float32 256^3 | 58.965 ms | 31.153 ms | 16.962 ms | 9.612 ms | 11.774 ms | 7.543 ms | 3.750 ms | 1.917 ms | — | 3.594 ms | 1.280 ms | 248.863 μs |
| interpolate! trilinear | Float32 512^3 | — | — | — | — | 427.921 ms | 227.216 ms | 123.954 ms | 61.971 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 229.927 μs | 130.069 μs | 79.441 μs | 55.421 μs | 146.941 μs | 79.541 μs | 47.510 μs | 33.160 μs | 65.160 μs | 1.448 ms | 957.585 μs | 64.610 μs |
| interpolate! trilinear | Float64 128^3 | 2.701 ms | 1.303 ms | 684.250 μs | 376.231 μs | 1.352 ms | 687.227 μs | 359.874 μs | 189.312 μs | 325.503 μs | 1.772 ms | 1.092 ms | 87.331 μs |
| interpolate! trilinear | Float64 256^3 | 63.559 ms | 34.975 ms | 21.773 ms | 14.148 ms | 33.627 ms | 17.050 ms | 8.482 ms | 4.137 ms | — | 4.014 ms | 1.595 ms | 422.824 μs |
| interpolate! trilinear | Float64 512^3 | — | — | — | — | 437.161 ms | 257.368 ms | 123.206 ms | 67.696 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 243.070 μs | 135.937 μs | 83.635 μs | 59.224 μs | 161.642 μs | 86.361 μs | 49.661 μs | 33.820 μs | 65.930 μs | 1.530 ms | 1.083 ms | 63.071 μs |

## reductions

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.254 ms | 7.184 ms | 7.518 ms | 8.042 ms | 6.977 ms | 4.983 ms | 5.854 ms | 6.076 ms | 2.099 ms | 27.761 ms | 1.656 ms | 295.563 μs |
| co-spectrum vec.vec | Float32 256^3 | 67.299 ms | 48.661 ms | 44.719 ms | 41.361 ms | 55.798 ms | 36.797 ms | 32.204 ms | 29.728 ms | — | 97.666 ms | 3.211 ms | 962.460 μs |
| co-spectrum vec.vec | Float32 512^3 | — | — | — | — | 449.256 ms | 268.976 ms | 189.676 ms | 153.387 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.066 ms | 1.312 ms | 1.499 ms | 1.608 ms | 903.205 μs | 937.399 μs | 1.236 ms | 1.355 ms | 491.824 μs | 17.761 ms | 1.383 ms | 188.612 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.657 ms | 6.773 ms | 6.126 ms | 5.353 ms | 7.245 ms | 5.170 ms | 4.532 ms | 4.476 ms | 2.194 ms | 29.708 ms | 29.468 ms | 381.234 μs |
| co-spectrum vec.vec | Float64 256^3 | 69.632 ms | 48.804 ms | 36.231 ms | 30.082 ms | 58.819 ms | 37.194 ms | 27.287 ms | 22.679 ms | — | 109.563 ms | 66.321 ms | 1.394 ms |
| co-spectrum vec.vec | Float64 512^3 | — | — | — | — | 464.038 ms | 284.763 ms | 185.324 ms | 130.852 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.085 ms | 825.029 μs | 980.776 μs | 1.003 ms | 940.380 μs | 746.697 μs | 854.400 μs | 937.029 μs | 482.135 μs | 16.075 ms | 16.001 ms | 193.152 μs |
| cross-correlation vec.vec | Float32 128^3 | 39.547 ms | 34.663 ms | 36.194 ms | 38.616 ms | 32.893 ms | 24.114 ms | 21.465 ms | 21.851 ms | 5.891 ms | 43.640 ms | 2.622 ms | 680.057 μs |
| cross-correlation vec.vec | Float32 256^3 | 474.252 ms | 310.305 ms | 279.929 ms | 270.474 ms | 403.371 ms | 271.339 ms | 201.280 ms | 173.269 ms | — | 186.915 ms | 10.470 ms | 5.849 ms |
| cross-correlation vec.vec | Float32 512^3 | — | — | — | — | 3.137 s | 2.029 s | 1.442 s | 1.145 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.749 ms | 5.378 ms | 6.182 ms | 6.182 ms | 3.877 ms | 3.618 ms | 3.854 ms | 3.691 ms | 1.025 ms | 20.682 ms | 1.467 ms | 306.153 μs |
| cross-correlation vec.vec | Float64 128^3 | 62.493 ms | 61.925 ms | 56.674 ms | 51.020 ms | 53.205 ms | 41.271 ms | 34.515 ms | 31.161 ms | 9.144 ms | 52.055 ms | 51.351 ms | 2.096 ms |
| cross-correlation vec.vec | Float64 256^3 | 694.984 ms | 487.096 ms | 402.316 ms | 373.900 ms | 575.562 ms | 381.599 ms | 286.364 ms | 258.713 ms | — | 217.471 ms | 137.382 ms | 16.317 ms |
| cross-correlation vec.vec | Float64 512^3 | — | — | — | — | 4.524 s | 2.921 s | 2.064 s | 1.809 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.865 ms | 5.997 ms | 5.802 ms | 6.028 ms | 4.185 ms | 3.566 ms | 3.437 ms | 3.336 ms | 1.557 ms | 20.881 ms | 23.884 ms | 332.384 μs |
| inner spectral | Float32 128^3 | 2.563 ms | 1.791 ms | 1.452 ms | 1.334 ms | 1.500 ms | 860.529 μs | 536.966 μs | 415.294 μs | 669.926 μs | 2.049 ms | 1.209 ms | 291.923 μs |
| inner spectral | Float32 256^3 | 23.278 ms | 18.210 ms | 16.587 ms | 15.600 ms | 13.391 ms | 8.725 ms | 7.407 ms | 7.652 ms | — | 3.999 ms | 1.750 ms | 775.378 μs |
| inner spectral | Float32 512^3 | — | — | — | — | 110.291 ms | 84.940 ms | 73.428 ms | 76.514 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 311.019 μs | 205.978 μs | 149.325 μs | 120.701 μs | 228.252 μs | 133.361 μs | 99.771 μs | 88.661 μs | 275.972 μs | 1.780 ms | 1.135 ms | 235.093 μs |
| inner spectral | Float64 128^3 | 4.413 ms | 3.674 ms | 3.246 ms | 3.123 ms | 1.901 ms | 1.221 ms | 777.359 μs | 683.827 μs | 811.337 μs | 2.410 ms | 1.363 ms | 370.523 μs |
| inner spectral | Float64 256^3 | 38.299 ms | 32.438 ms | 29.665 ms | 28.720 ms | 18.086 ms | 16.401 ms | 16.744 ms | 17.628 ms | — | 7.953 ms | 2.789 ms | 1.268 ms |
| inner spectral | Float64 512^3 | — | — | — | — | 137.203 ms | 129.873 ms | 128.502 ms | 129.552 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 320.843 μs | 216.120 μs | 156.316 μs | 128.354 μs | 219.772 μs | 148.962 μs | 102.211 μs | 98.591 μs | 293.003 μs | 1.765 ms | 1.138 ms | 253.033 μs |
| inner vec.vec | Float32 128^3 | 1.342 ms | 990.184 μs | 839.085 μs | 784.529 μs | 369.922 μs | 191.282 μs | 99.701 μs | 72.701 μs | 308.353 μs | 1.623 ms | 794.094 μs | 118.101 μs |
| inner vec.vec | Float32 256^3 | 14.293 ms | 12.958 ms | 12.083 ms | 11.385 ms | 6.878 ms | 5.983 ms | 5.874 ms | 5.939 ms | — | 3.382 ms | 1.298 ms | 574.286 μs |
| inner vec.vec | Float32 512^3 | — | — | — | — | 62.609 ms | 57.132 ms | 55.907 ms | 56.080 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 70.561 μs | 40.413 μs | 21.692 μs | 15.246 μs | 45.500 μs | 26.640 μs | 14.600 μs | 9.861 μs | 98.731 μs | 1.278 ms | 774.243 μs | 83.621 μs |
| inner vec.vec | Float64 128^3 | 3.170 ms | 2.654 ms | 2.422 ms | 2.283 ms | 1.251 ms | 512.535 μs | 304.574 μs | 226.222 μs | 552.615 μs | 1.860 ms | 998.015 μs | 236.233 μs |
| inner vec.vec | Float64 256^3 | 27.690 ms | 25.846 ms | 24.166 ms | 22.893 ms | 14.848 ms | 13.848 ms | 13.504 ms | 13.303 ms | — | 5.634 ms | 2.038 ms | 1.069 ms |
| inner vec.vec | Float64 512^3 | — | — | — | — | 122.787 ms | 111.968 ms | 110.121 ms | 110.924 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 140.726 μs | 79.148 μs | 42.532 μs | 26.139 μs | 87.571 μs | 46.650 μs | 26.341 μs | 17.680 μs | 162.792 μs | 1.434 ms | 777.319 μs | 108.632 μs |
| integral scalar | Float32 128^3 | 111.663 μs | 62.237 μs | 31.233 μs | 20.314 μs | 69.941 μs | 36.950 μs | 19.350 μs | 12.620 μs | 228.932 μs | 1.318 ms | 1.144 ms | 105.611 μs |
| integral scalar | Float32 256^3 | 2.158 ms | 1.576 ms | 1.356 ms | 1.256 ms | 538.114 μs | 311.623 μs | 140.922 μs | 98.961 μs | — | 9.002 ms | 2.302 ms | 257.993 μs |
| integral scalar | Float32 512^3 | — | — | — | — | 10.473 ms | 9.027 ms | 8.866 ms | 8.809 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 9.716 μs | 6.790 μs | 5.853 μs | 6.149 μs | 6.950 μs | 4.868 μs | 3.931 μs | 4.925 μs | 95.301 μs | 1.534 ms | 899.409 μs | 81.571 μs |
| integral scalar | Float64 128^3 | 237.317 μs | 131.226 μs | 68.405 μs | 39.071 μs | 124.321 μs | 63.380 μs | 37.310 μs | 23.721 μs | 221.812 μs | 2.553 ms | 1.192 ms | 99.621 μs |
| integral scalar | Float64 256^3 | 4.624 ms | 3.807 ms | 3.490 ms | 3.241 ms | 1.898 ms | 1.125 ms | 845.569 μs | 975.790 μs | — | 10.817 ms | 2.694 ms | 272.993 μs |
| integral scalar | Float64 512^3 | — | — | — | — | 18.913 ms | 18.456 ms | 17.895 ms | 18.245 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.823 μs | 13.214 μs | 8.356 μs | 8.211 μs | 15.240 μs | 7.550 μs | 5.930 μs | 6.010 μs | 95.391 μs | 1.583 ms | 853.383 μs | 81.661 μs |
| integral spectral vec | Float32 128^3 | 73.574 ns | 68.827 ns | 68.706 ns | 69.278 ns | 69.253 ns | 70.553 ns | 68.411 ns | 69.151 ns | — | — | 847.189 μs | 47.390 μs |
| integral spectral vec | Float32 256^3 | 73.413 ns | 68.980 ns | 69.976 ns | 69.051 ns | 69.591 ns | 71.178 ns | 68.944 ns | 69.211 ns | — | — | 812.731 μs | 47.810 μs |
| integral spectral vec | Float32 512^3 | — | — | — | — | 71.220 ns | 74.335 ns | 72.116 ns | 70.083 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 72.717 ns | 71.669 ns | 68.260 ns | 68.346 ns | 68.791 ns | 72.264 ns | 69.497 ns | 72.098 ns | — | — | 833.215 μs | 46.071 μs |
| integral spectral vec | Float64 128^3 | 75.348 ns | 70.247 ns | 71.222 ns | 70.787 ns | 73.552 ns | 73.649 ns | 75.181 ns | 72.063 ns | — | — | 832.384 μs | 50.161 μs |
| integral spectral vec | Float64 256^3 | 76.678 ns | 71.125 ns | 71.996 ns | 72.808 ns | 75.068 ns | 75.561 ns | 76.372 ns | 72.504 ns | — | — | 808.714 μs | 47.391 μs |
| integral spectral vec | Float64 512^3 | — | — | — | — | 76.418 ns | 79.600 ns | 80.864 ns | 77.646 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 72.326 ns | 69.628 ns | 69.560 ns | 70.826 ns | 76.184 ns | 74.934 ns | 77.630 ns | 74.681 ns | — | — | 842.906 μs | 45.900 μs |
| l2norm vec | Float32 128^3 | 640.793 μs | 338.018 μs | 186.032 μs | 92.844 μs | 240.012 μs | 122.461 μs | 64.160 μs | 39.591 μs | 196.632 μs | 1.582 ms | 854.011 μs | 101.161 μs |
| l2norm vec | Float32 256^3 | 8.328 ms | 6.167 ms | 5.599 ms | 5.442 ms | 4.094 ms | 2.439 ms | 1.964 ms | 2.003 ms | — | 3.219 ms | 1.301 ms | 344.544 μs |
| l2norm vec | Float32 512^3 | — | — | — | — | 40.853 ms | 30.534 ms | 27.158 ms | 27.221 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 50.794 μs | 27.610 μs | 15.886 μs | 11.830 μs | 30.070 μs | 16.320 μs | 9.611 μs | 6.870 μs | 85.641 μs | 1.361 ms | 756.839 μs | 91.490 μs |
| l2norm vec | Float64 128^3 | 1.712 ms | 1.077 ms | 827.080 μs | 779.411 μs | 533.454 μs | 251.383 μs | 128.701 μs | 78.161 μs | 344.333 μs | 1.876 ms | 978.559 μs | 142.751 μs |
| l2norm vec | Float64 256^3 | 15.793 ms | 12.600 ms | 11.618 ms | 11.037 ms | 9.658 ms | 6.876 ms | 5.764 ms | 5.616 ms | — | 5.670 ms | 1.957 ms | 604.386 μs |
| l2norm vec | Float64 512^3 | — | — | — | — | 84.973 ms | 61.940 ms | 54.523 ms | 54.920 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 94.189 μs | 53.113 μs | 28.482 μs | 18.489 μs | 56.281 μs | 29.010 μs | 17.060 μs | 10.720 μs | 134.871 μs | 1.402 ms | 773.034 μs | 106.222 μs |
| lpnorm vec Inf | Float32 128^3 | 1.389 ms | 1.370 ms | 1.146 ms | 1.040 ms | 461.963 μs | 386.214 μs | 323.883 μs | 308.894 μs | 592.145 μs | 3.080 ms | 1.319 ms | 145.392 μs |
| lpnorm vec Inf | Float32 256^3 | 22.791 ms | 14.822 ms | 12.193 ms | 11.084 ms | 18.848 ms | 8.516 ms | 8.736 ms | 8.737 ms | — | 13.216 ms | 3.421 ms | 589.536 μs |
| lpnorm vec Inf | Float32 512^3 | — | — | — | — | 128.784 ms | 87.045 ms | 72.760 ms | 73.011 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 98.887 μs | 92.210 μs | 73.501 μs | 78.929 μs | 60.800 μs | 48.540 μs | 41.811 μs | 42.191 μs | 155.751 μs | 1.641 ms | 964.230 μs | 116.972 μs |
| lpnorm vec Inf | Float64 128^3 | 3.310 ms | 3.191 ms | 2.602 ms | 2.600 ms | 1.077 ms | 1.076 ms | 1.069 ms | 986.500 μs | 660.476 μs | 3.883 ms | 1.668 ms | 235.973 μs |
| lpnorm vec Inf | Float64 256^3 | 47.266 ms | 31.386 ms | 24.155 ms | 22.468 ms | 32.246 ms | 21.661 ms | 17.579 ms | 17.279 ms | — | 14.730 ms | 5.382 ms | 967.850 μs |
| lpnorm vec Inf | Float64 512^3 | — | — | — | — | 246.039 ms | 159.577 ms | 138.951 ms | 137.711 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 238.281 μs | 179.555 μs | 154.396 μs | 145.295 μs | 111.451 μs | 91.231 μs | 75.711 μs | 72.071 μs | 166.092 μs | 1.711 ms | 1.005 ms | 114.831 μs |
| maximum scalar | Float32 128^3 | 345.259 μs | 177.509 μs | 92.029 μs | 51.200 μs | 238.042 μs | 118.691 μs | 59.981 μs | 32.850 μs | 223.322 μs | 2.331 ms | 1.146 ms | 94.331 μs |
| maximum scalar | Float32 256^3 | 2.903 ms | 1.818 ms | 1.454 ms | 1.335 ms | 1.885 ms | 957.899 μs | 482.986 μs | 249.422 μs | — | 9.121 ms | 2.319 ms | 252.853 μs |
| maximum scalar | Float32 512^3 | — | — | — | — | 29.765 ms | 11.827 ms | 9.720 ms | 8.196 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 43.017 μs | 24.700 μs | 14.813 μs | 11.942 μs | 29.440 μs | 15.700 μs | 9.330 μs | 6.600 μs | 101.731 μs | 1.564 ms | 922.422 μs | 86.591 μs |
| maximum scalar | Float64 128^3 | 547.286 μs | 291.499 μs | 144.142 μs | 79.381 μs | 444.893 μs | 220.802 μs | 114.191 μs | 59.060 μs | 244.072 μs | 2.772 ms | 1.301 ms | 106.871 μs |
| maximum scalar | Float64 256^3 | 6.082 ms | 4.302 ms | 3.627 ms | 3.355 ms | 4.949 ms | 2.385 ms | 1.282 ms | 826.918 μs | — | 12.659 ms | 3.329 ms | 297.583 μs |
| maximum scalar | Float64 512^3 | — | — | — | — | 43.333 ms | 26.765 ms | 18.516 ms | 17.593 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 66.519 μs | 37.472 μs | 20.447 μs | 14.675 μs | 55.371 μs | 29.510 μs | 15.921 μs | 10.140 μs | 99.451 μs | 1.634 ms | 947.833 μs | 95.681 μs |
| maximum(norm) vec | Float32 128^3 | 1.840 ms | 927.308 μs | 474.221 μs | 246.021 μs | 775.556 μs | 390.284 μs | 198.852 μs | 104.192 μs | — | — | 1.234 ms | 112.751 μs |
| maximum(norm) vec | Float32 256^3 | 15.152 ms | 8.494 ms | 5.995 ms | 5.604 ms | 8.588 ms | 4.181 ms | 2.442 ms | 2.166 ms | — | — | 2.782 ms | 373.803 μs |
| maximum(norm) vec | Float32 512^3 | — | — | — | — | 60.001 ms | 39.016 ms | 29.361 ms | 28.110 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 225.159 μs | 118.554 μs | 62.180 μs | 48.872 μs | 96.530 μs | 50.181 μs | 26.430 μs | 15.550 μs | — | — | 920.168 μs | 91.301 μs |
| maximum(norm) vec | Float64 128^3 | 5.345 ms | 2.715 ms | 1.393 ms | 846.954 μs | 1.587 ms | 793.127 μs | 399.885 μs | 202.872 μs | — | — | 1.571 ms | 218.683 μs |
| maximum(norm) vec | Float64 256^3 | 43.178 ms | 22.282 ms | 13.330 ms | 11.568 ms | 15.484 ms | 8.002 ms | 6.038 ms | 5.817 ms | — | — | 4.860 ms | 1.054 ms |
| maximum(norm) vec | Float64 512^3 | — | — | — | — | 120.005 ms | 70.789 ms | 55.949 ms | 55.828 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 651.615 μs | 337.108 μs | 170.646 μs | 90.136 μs | 197.332 μs | 101.191 μs | 52.101 μs | 28.460 μs | — | — | 979.833 μs | 103.191 μs |
| mean spectral vec | Float32 128^3 | 71.740 ns | 71.533 ns | 71.579 ns | 72.110 ns | 71.508 ns | 72.434 ns | 72.999 ns | 71.337 ns | — | — | 820.577 μs | 51.500 μs |
| mean spectral vec | Float32 256^3 | 72.239 ns | 72.320 ns | 72.756 ns | 72.872 ns | 71.457 ns | 73.344 ns | 73.215 ns | 71.266 ns | — | — | 812.941 μs | 52.441 μs |
| mean spectral vec | Float32 512^3 | — | — | — | — | 73.345 ns | 76.059 ns | 76.099 ns | 75.746 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 77.463 ns | 71.234 ns | 71.368 ns | 71.759 ns | 71.087 ns | 73.931 ns | 73.948 ns | 72.938 ns | — | — | 833.055 μs | 46.190 μs |
| mean spectral vec | Float64 128^3 | 77.758 ns | 73.848 ns | 74.286 ns | 74.398 ns | 76.021 ns | 77.181 ns | 78.398 ns | 82.426 ns | — | — | 814.812 μs | 49.260 μs |
| mean spectral vec | Float64 256^3 | 79.716 ns | 74.563 ns | 75.460 ns | 76.613 ns | 76.327 ns | 79.630 ns | 78.720 ns | 84.598 ns | — | — | 848.819 μs | 54.651 μs |
| mean spectral vec | Float64 512^3 | — | — | — | — | 78.866 ns | 84.108 ns | 84.185 ns | 88.028 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 73.504 ns | 73.021 ns | 72.737 ns | 73.951 ns | 78.369 ns | 79.390 ns | 80.912 ns | 85.162 ns | — | — | 830.467 μs | 47.681 μs |
| mean vector | Float32 128^3 | 521.620 μs | 319.670 μs | 194.991 μs | 114.663 μs | 213.431 μs | 112.591 μs | 66.240 μs | 53.630 μs | 633.756 μs | 4.808 ms | 1.887 ms | 198.432 μs |
| mean vector | Float32 256^3 | 7.827 ms | 6.072 ms | 5.559 ms | 5.436 ms | 3.273 ms | 2.372 ms | 2.392 ms | 2.488 ms | — | 16.657 ms | 5.531 ms | 674.917 μs |
| mean vector | Float32 512^3 | — | — | — | — | 30.898 ms | 28.467 ms | 27.351 ms | 27.568 ms | — | — | — | — |
| mean vector | Float32 64^3 | 49.165 μs | 34.264 μs | 25.674 μs | 31.341 μs | 31.520 μs | 21.750 μs | 18.410 μs | 22.950 μs | 162.362 μs | 1.846 ms | 1.302 ms | 179.872 μs |
| mean vector | Float64 128^3 | 1.648 ms | 1.053 ms | 849.643 μs | 793.726 μs | 413.753 μs | 213.432 μs | 116.511 μs | 87.731 μs | 657.486 μs | 5.195 ms | 1.836 ms | 218.432 μs |
| mean vector | Float64 256^3 | 14.983 ms | 12.972 ms | 11.806 ms | 11.316 ms | 7.328 ms | 6.892 ms | 6.665 ms | 6.721 ms | — | 17.799 ms | 6.369 ms | 706.207 μs |
| mean vector | Float64 512^3 | — | — | — | — | 59.204 ms | 56.170 ms | 54.402 ms | 55.032 ms | — | — | — | — |
| mean vector | Float64 64^3 | 92.415 μs | 63.766 μs | 41.668 μs | 40.850 μs | 54.711 μs | 36.511 μs | 26.251 μs | 26.580 μs | 156.311 μs | 1.913 ms | 1.281 ms | 172.422 μs |
| mean(det) tensor | Float32 128^3 | 2.495 ms | 1.968 ms | 1.694 ms | 1.532 ms | 799.036 μs | 377.144 μs | 192.442 μs | 122.631 μs | — | — | 1.280 ms | 212.723 μs |
| mean(det) tensor | Float32 256^3 | 24.807 ms | 21.499 ms | 19.098 ms | 17.978 ms | 15.076 ms | 11.732 ms | 10.413 ms | 10.414 ms | — | — | 3.413 ms | 831.058 μs |
| mean(det) tensor | Float32 512^3 | — | — | — | — | 103.668 ms | 89.927 ms | 83.988 ms | 86.081 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 103.122 μs | 61.466 μs | 29.994 μs | 21.224 μs | 66.860 μs | 36.940 μs | 22.580 μs | 15.360 μs | — | — | 937.045 μs | 95.331 μs |
| mean(det) tensor | Float64 128^3 | 5.384 ms | 4.754 ms | 4.222 ms | 3.863 ms | 2.566 ms | 1.517 ms | 1.195 ms | 1.203 ms | — | — | 1.491 ms | 330.033 μs |
| mean(det) tensor | Float64 256^3 | 46.354 ms | 44.532 ms | 38.506 ms | 37.166 ms | 25.156 ms | 21.767 ms | 21.454 ms | 21.518 ms | — | — | 4.560 ms | 1.537 ms |
| mean(det) tensor | Float64 512^3 | — | — | — | — | 195.271 ms | 174.392 ms | 167.742 ms | 169.356 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 233.464 μs | 129.918 μs | 74.662 μs | 41.508 μs | 129.341 μs | 68.121 μs | 36.530 μs | 28.590 μs | — | — | 972.637 μs | 108.071 μs |
| mean(norm) vec | Float32 128^3 | 1.589 ms | 806.356 μs | 407.919 μs | 212.917 μs | 609.074 μs | 301.492 μs | 154.782 μs | 84.921 μs | — | — | 538.869 μs | 108.861 μs |
| mean(norm) vec | Float32 256^3 | 13.152 ms | 7.866 ms | 5.982 ms | 5.545 ms | 7.611 ms | 3.750 ms | 2.352 ms | 2.165 ms | — | — | 2.833 ms | 370.554 μs |
| mean(norm) vec | Float32 512^3 | — | — | — | — | 54.563 ms | 37.004 ms | 29.186 ms | 28.254 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 193.009 μs | 99.359 μs | 53.467 μs | 31.969 μs | 75.991 μs | 39.130 μs | 21.110 μs | 12.960 μs | — | — | 921.051 μs | 92.241 μs |
| mean(norm) vec | Float64 128^3 | 5.283 ms | 2.668 ms | 1.367 ms | 852.780 μs | 1.430 ms | 717.267 μs | 364.094 μs | 188.562 μs | — | — | 1.332 ms | 219.723 μs |
| mean(norm) vec | Float64 256^3 | 42.797 ms | 21.618 ms | 13.196 ms | 11.503 ms | 13.776 ms | 7.949 ms | 5.892 ms | 5.798 ms | — | — | 4.325 ms | 948.140 μs |
| mean(norm) vec | Float64 512^3 | — | — | — | — | 107.804 ms | 68.343 ms | 55.710 ms | 55.805 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 644.557 μs | 332.750 μs | 168.447 μs | 89.317 μs | 178.391 μs | 92.750 μs | 47.681 μs | 26.170 μs | — | — | 957.695 μs | 102.211 μs |
| mean(tr) tensor | Float32 128^3 | 376.803 μs | 234.813 μs | 139.321 μs | 73.191 μs | 197.922 μs | 97.161 μs | 51.460 μs | 35.900 μs | — | — | 1.200 ms | 114.201 μs |
| mean(tr) tensor | Float32 256^3 | 6.684 ms | 6.358 ms | 5.667 ms | 5.460 ms | 3.108 ms | 2.410 ms | 2.185 ms | 2.264 ms | — | — | 2.699 ms | 361.374 μs |
| mean(tr) tensor | Float32 512^3 | — | — | — | — | 32.596 ms | 28.918 ms | 27.596 ms | 28.194 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 34.871 μs | 18.654 μs | 11.294 μs | 10.156 μs | 24.620 μs | 12.930 μs | 7.030 μs | 6.460 μs | — | — | 910.276 μs | 98.661 μs |
| mean(tr) tensor | Float64 128^3 | 1.325 ms | 985.412 μs | 838.504 μs | 748.239 μs | 398.823 μs | 177.712 μs | 100.271 μs | 70.140 μs | — | — | 1.170 ms | 158.772 μs |
| mean(tr) tensor | Float64 256^3 | 13.247 ms | 13.083 ms | 11.902 ms | 11.275 ms | 6.343 ms | 6.363 ms | 6.252 ms | 6.191 ms | — | — | 3.285 ms | 600.256 μs |
| mean(tr) tensor | Float64 512^3 | — | — | — | — | 69.476 ms | 57.031 ms | 55.089 ms | 55.604 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 67.856 μs | 37.556 μs | 20.285 μs | 15.147 μs | 49.171 μs | 24.480 μs | 13.831 μs | 9.860 μs | — | — | 921.594 μs | 86.781 μs |
| radial_correlation vec | Float32 128^3 | 37.712 ms | 33.033 ms | 35.793 ms | 36.040 ms | 30.370 ms | 22.216 ms | 21.395 ms | 21.202 ms | 5.783 ms | 42.875 ms | 2.515 ms | 643.497 μs |
| radial_correlation vec | Float32 256^3 | 447.565 ms | 308.865 ms | 277.883 ms | 264.189 ms | 379.957 ms | 258.234 ms | 198.312 ms | 170.425 ms | — | 185.439 ms | 10.286 ms | 5.638 ms |
| radial_correlation vec | Float32 512^3 | — | — | — | — | 2.975 s | 1.865 s | 1.354 s | 1.126 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.485 ms | 5.199 ms | 5.976 ms | 5.911 ms | 3.534 ms | 3.365 ms | 3.695 ms | 3.577 ms | 1.010 ms | 19.917 ms | 1.555 ms | 304.413 μs |
| radial_correlation vec | Float64 128^3 | 60.402 ms | 62.099 ms | 54.644 ms | 51.117 ms | 50.485 ms | 39.474 ms | 32.722 ms | 29.221 ms | 9.025 ms | 52.060 ms | 47.229 ms | 2.034 ms |
| radial_correlation vec | Float64 256^3 | 673.902 ms | 474.417 ms | 394.981 ms | 361.825 ms | 538.382 ms | 367.357 ms | 277.070 ms | 251.098 ms | — | 219.151 ms | 138.359 ms | 14.779 ms |
| radial_correlation vec | Float64 512^3 | — | — | — | — | 4.303 s | 2.849 s | 2.020 s | 1.744 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.555 ms | 5.140 ms | 5.663 ms | 5.733 ms | 3.814 ms | 3.237 ms | 3.279 ms | 3.082 ms | 1.413 ms | 21.203 ms | 23.553 ms | 327.584 μs |
| radial_spectrum vec | Float32 128^3 | 7.687 ms | 7.368 ms | 8.086 ms | 8.080 ms | 6.320 ms | 4.752 ms | 5.770 ms | 6.331 ms | 1.415 ms | 27.166 ms | 1.792 ms | 302.443 μs |
| radial_spectrum vec | Float32 256^3 | 61.536 ms | 48.600 ms | 45.891 ms | 43.702 ms | 50.076 ms | 32.918 ms | 31.370 ms | 30.748 ms | — | 96.772 ms | 3.246 ms | 953.010 μs |
| radial_spectrum vec | Float32 512^3 | — | — | — | — | 399.329 ms | 241.891 ms | 181.231 ms | 159.316 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 998.613 μs | 1.333 ms | 1.599 ms | 1.621 ms | 821.855 μs | 938.949 μs | 1.188 ms | 1.398 ms | 344.443 μs | 16.995 ms | 1.190 ms | 200.133 μs |
| radial_spectrum vec | Float64 128^3 | 7.731 ms | 6.612 ms | 5.934 ms | 5.548 ms | 6.541 ms | 4.652 ms | 4.438 ms | 4.560 ms | 1.515 ms | 29.791 ms | 28.854 ms | 382.194 μs |
| radial_spectrum vec | Float64 256^3 | 62.255 ms | 46.066 ms | 36.465 ms | 30.301 ms | 51.958 ms | 32.347 ms | 25.152 ms | 24.258 ms | — | 110.504 ms | 67.077 ms | 1.382 ms |
| radial_spectrum vec | Float64 512^3 | — | — | — | — | 414.008 ms | 252.478 ms | 162.975 ms | 126.186 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 1.008 ms | 774.067 μs | 1.104 ms | 1.102 ms | 852.038 μs | 707.797 μs | 826.870 μs | 940.480 μs | 380.613 μs | 16.740 ms | 15.470 ms | 193.112 μs |
| weighted_inner vec | Float32 128^3 | 12.776 ms | 12.629 ms | 12.608 ms | 12.786 ms | 10.361 ms | 10.389 ms | 10.341 ms | 10.337 ms | — | — | 1.428 ms | 156.591 μs |
| weighted_inner vec | Float32 256^3 | 100.807 ms | 100.234 ms | 99.130 ms | 100.881 ms | 81.590 ms | 81.486 ms | 81.453 ms | 81.288 ms | — | — | 4.280 ms | 647.166 μs |
| weighted_inner vec | Float32 512^3 | — | — | — | — | 646.432 ms | 646.634 ms | 647.639 ms | 646.797 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.629 ms | 1.624 ms | 1.626 ms | 1.629 ms | 1.286 ms | 1.286 ms | 1.283 ms | 1.345 ms | — | — | 1.020 ms | 105.021 μs |
| weighted_inner vec | Float64 128^3 | 13.991 ms | 13.956 ms | 13.886 ms | 13.759 ms | 10.918 ms | 10.908 ms | 10.889 ms | 10.987 ms | — | — | 1.679 ms | 169.432 μs |
| weighted_inner vec | Float64 256^3 | 110.973 ms | 111.552 ms | 111.245 ms | 108.115 ms | 85.722 ms | 90.548 ms | 85.826 ms | 85.941 ms | — | — | 5.232 ms | 1.074 ms |
| weighted_inner vec | Float64 512^3 | — | — | — | — | 680.975 ms | 681.663 ms | 681.940 ms | 681.562 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.725 ms | 1.725 ms | 1.722 ms | 1.715 ms | 1.410 ms | 1.350 ms | 1.411 ms | 1.357 ms | — | — | 1.040 ms | 103.381 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.869 ms | 12.646 ms | 12.697 ms | 12.786 ms | 10.397 ms | 10.333 ms | 10.334 ms | 10.297 ms | — | — | 1.362 ms | 174.872 μs |
| weighted_inner vec.vec | Float32 256^3 | 101.877 ms | 100.494 ms | 99.619 ms | 101.362 ms | 81.733 ms | 81.599 ms | 81.692 ms | 81.404 ms | — | — | 4.195 ms | 836.039 μs |
| weighted_inner vec.vec | Float32 512^3 | — | — | — | — | 647.969 ms | 647.543 ms | 648.645 ms | 648.198 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.632 ms | 1.626 ms | 1.628 ms | 1.599 ms | 1.301 ms | 1.290 ms | 1.308 ms | 1.359 ms | — | — | 1.001 ms | 95.201 μs |
| weighted_inner vec.vec | Float64 128^3 | 14.076 ms | 14.115 ms | 14.233 ms | 13.824 ms | 10.928 ms | 10.933 ms | 10.942 ms | 10.998 ms | — | — | 1.584 ms | 261.853 μs |
| weighted_inner vec.vec | Float64 256^3 | 112.210 ms | 112.428 ms | 114.038 ms | 110.747 ms | 85.922 ms | 86.084 ms | 86.032 ms | 86.283 ms | — | — | 5.332 ms | 1.544 ms |
| weighted_inner vec.vec | Float64 512^3 | — | — | — | — | 682.464 ms | 685.231 ms | 683.161 ms | 683.835 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.743 ms | 1.729 ms | 1.743 ms | 1.705 ms | 1.415 ms | 1.384 ms | 1.427 ms | 1.400 ms | — | — | 985.284 μs | 100.961 μs |

