# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-07-22 at commit `a7aad85` on Julia 1.12.6, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–256³) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB; columns measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone; the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The `Aiporetne` columns (12700K, 6700 XT, 7900 XTX) predate the decision-38/39 rewrite and refresh on that host's next sweep. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh` plus the per-card / per-CPU archive in `benchmark/results/` (PERFORMANCE.md §6). ~10% jitter.

## fft

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 5.185 ms | 3.332 ms | 2.425 ms | 2.386 ms | 4.694 ms | 2.358 ms | 1.276 ms | 766.597 μs | 788.067 μs | 2.421 ms | 435.844 μs | 119.432 μs |
| to_physical scalar | Float32 256^3 | 120.456 ms | 75.085 ms | 39.701 ms | 37.317 ms | 185.631 ms | 100.977 ms | 56.725 ms | 35.913 ms | — | 7.945 ms | 1.492 ms | 1.082 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | 2.102 s | 1.121 s | 629.538 ms | 391.987 ms | — | — | — | — |
| to_physical scalar | Float32 64^3 | 404.712 μs | 256.238 μs | 172.228 μs | 141.909 μs | 313.733 μs | 176.991 μs | 102.071 μs | 70.731 μs | 124.402 μs | 1.497 ms | 335.253 μs | 116.271 μs |
| to_physical scalar | Float64 128^3 | 8.342 ms | 5.868 ms | 5.057 ms | 4.609 ms | 10.098 ms | 5.437 ms | 3.023 ms | 1.814 ms | 1.905 ms | 3.750 ms | 904.753 μs | 493.576 μs |
| to_physical scalar | Float64 256^3 | 154.523 ms | 104.915 ms | 86.850 ms | 81.789 ms | 113.758 ms | 72.813 ms | 52.678 ms | 38.243 ms | — | 14.463 ms | 5.261 ms | 3.828 ms |
| to_physical scalar | Float64 512^3 | — | — | — | — | 938.673 ms | 616.490 ms | 455.138 ms | 412.947 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 699.028 μs | 443.724 μs | 318.737 μs | 267.959 μs | 520.215 μs | 293.813 μs | 165.502 μs | 113.061 μs | 331.873 μs | 1.784 ms | 392.529 μs | 126.861 μs |
| to_physical vector | Float32 128^3 | 15.516 ms | 11.976 ms | 8.329 ms | 8.304 ms | 14.441 ms | 10.194 ms | 5.241 ms | 3.770 ms | 2.507 ms | 4.595 ms | 826.947 μs | 303.484 μs |
| to_physical vector | Float32 256^3 | 376.172 ms | 273.666 ms | 172.548 ms | 146.567 ms | 593.375 ms | 412.807 ms | 220.879 ms | 161.935 ms | — | 14.844 ms | 5.000 ms | 3.475 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | 6.264 s | 4.295 s | 2.292 s | 1.655 s | — | — | — | — |
| to_physical vector | Float32 64^3 | 1.327 ms | 997.886 μs | 541.102 μs | 501.331 μs | 986.800 μs | 691.107 μs | 313.064 μs | 218.832 μs | 380.054 μs | 1.776 ms | 359.155 μs | 124.671 μs |
| to_physical vector | Float64 128^3 | 38.026 ms | 31.968 ms | 20.850 ms | 19.459 ms | 41.775 ms | 29.248 ms | 13.952 ms | 11.001 ms | 5.630 ms | 8.090 ms | 2.173 ms | 1.455 ms |
| to_physical vector | Float64 256^3 | 465.868 ms | 359.990 ms | 258.848 ms | 247.224 ms | 358.604 ms | 268.701 ms | 174.734 ms | 156.094 ms | — | 22.812 ms | 13.079 ms | 11.335 ms |
| to_physical vector | Float64 512^3 | — | — | — | — | 2.810 s | 2.123 s | 1.404 s | 1.254 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.791 ms | 2.220 ms | 1.596 ms | 1.213 ms | 1.627 ms | 1.123 ms | 559.505 μs | 425.434 μs | 811.437 μs | 2.301 ms | 618.297 μs | 203.172 μs |
| to_spectral scalar | Float32 128^3 | 4.656 ms | 2.812 ms | 1.691 ms | 1.605 ms | 4.577 ms | 2.267 ms | 1.228 ms | 701.236 μs | 488.254 μs | 2.072 ms | 358.889 μs | 94.781 μs |
| to_spectral scalar | Float32 256^3 | 118.430 ms | 71.360 ms | 36.322 ms | 26.415 ms | 187.531 ms | 101.587 ms | 55.296 ms | 33.987 ms | — | 5.009 ms | 991.167 μs | 729.758 μs |
| to_spectral scalar | Float32 512^3 | — | — | — | — | 2.085 s | 1.101 s | 604.970 ms | 363.802 ms | — | — | — | — |
| to_spectral scalar | Float32 64^3 | 383.004 μs | 218.234 μs | 132.117 μs | 114.514 μs | 308.093 μs | 167.252 μs | 90.861 μs | 58.901 μs | 89.181 μs | 1.538 ms | 355.056 μs | 81.641 μs |
| to_spectral scalar | Float64 128^3 | 7.445 ms | 5.217 ms | 4.181 ms | 3.436 ms | 10.407 ms | 5.423 ms | 2.870 ms | 1.662 ms | 1.501 ms | 3.125 ms | 826.771 μs | 429.816 μs |
| to_spectral scalar | Float64 256^3 | 173.710 ms | 109.655 ms | 80.023 ms | 68.113 ms | 209.455 ms | 115.748 ms | 57.997 ms | 45.507 ms | — | 12.871 ms | 4.227 ms | 3.122 ms |
| to_spectral scalar | Float64 512^3 | — | — | — | — | 1.721 s | 965.405 ms | 592.631 ms | 434.514 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 697.766 μs | 371.362 μs | 245.627 μs | 177.574 μs | 501.455 μs | 273.013 μs | 152.042 μs | 95.151 μs | 265.683 μs | 1.745 ms | 436.005 μs | 110.151 μs |
| to_spectral vector | Float32 128^3 | 14.196 ms | 10.079 ms | 6.842 ms | 6.110 ms | 14.952 ms | 10.575 ms | 5.189 ms | 3.379 ms | 1.355 ms | 3.183 ms | 473.980 μs | 192.732 μs |
| to_spectral vector | Float32 256^3 | 359.274 ms | 260.710 ms | 154.655 ms | 127.358 ms | 581.526 ms | 400.321 ms | 211.229 ms | 151.674 ms | — | 11.819 ms | 3.032 ms | 2.220 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | 6.235 s | 4.261 s | 2.212 s | 1.570 s | — | — | — | — |
| to_spectral vector | Float32 64^3 | 1.232 ms | 935.164 μs | 451.378 μs | 480.330 μs | 975.010 μs | 649.137 μs | 286.614 μs | 180.601 μs | 230.522 μs | 1.566 ms | 311.426 μs | 96.331 μs |
| to_spectral vector | Float64 128^3 | 34.978 ms | 30.297 ms | 19.984 ms | 18.093 ms | 41.892 ms | 30.029 ms | 13.163 ms | 9.962 ms | 4.144 ms | 6.538 ms | 1.592 ms | 1.170 ms |
| to_spectral vector | Float64 256^3 | 519.471 ms | 391.649 ms | 249.990 ms | 225.111 ms | 635.754 ms | 445.098 ms | 251.361 ms | 194.583 ms | — | 20.041 ms | 11.392 ms | 9.165 ms |
| to_spectral vector | Float64 512^3 | — | — | — | — | 5.055 s | 3.600 s | 2.031 s | 1.564 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.408 ms | 1.918 ms | 1.124 ms | 998.238 μs | 1.544 ms | 1.079 ms | 516.515 μs | 344.793 μs | 596.836 μs | 2.151 ms | 540.584 μs | 217.012 μs |

## algebra

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 432.952 μs | 3.604 ms | 1.846 ms | 949.549 μs | 161.712 μs | 84.051 μs | 44.570 μs | 34.700 μs | 351.303 μs | 1.943 ms | 397.824 μs | 79.791 μs |
| add! scalar | Float32 256^3 | 8.609 ms | 29.640 ms | 14.751 ms | 8.615 ms | 3.471 ms | 2.984 ms | 2.738 ms | 2.807 ms | — | 6.480 ms | 1.204 ms | 325.934 μs |
| add! scalar | Float32 512^3 | — | — | — | — | 40.521 ms | 36.516 ms | 36.715 ms | 37.318 ms | — | — | — | — |
| add! scalar | Float32 64^3 | 43.970 μs | 455.288 μs | 232.258 μs | 121.544 μs | 21.450 μs | 12.671 μs | 7.020 μs | 6.593 μs | 85.391 μs | 1.599 ms | 291.603 μs | 59.400 μs |
| add! scalar | Float64 128^3 | 1.546 ms | 3.635 ms | 1.861 ms | 1.118 ms | 326.784 μs | 165.042 μs | 87.041 μs | 72.791 μs | 354.693 μs | 2.024 ms | 379.045 μs | 98.381 μs |
| add! scalar | Float64 256^3 | 17.845 ms | 29.749 ms | 16.543 ms | 15.814 ms | 10.172 ms | 8.571 ms | 8.453 ms | 8.583 ms | — | 5.550 ms | 1.230 ms | 560.277 μs |
| add! scalar | Float64 512^3 | — | — | — | — | 83.759 ms | 73.022 ms | 73.425 ms | 74.315 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 85.313 μs | 462.446 μs | 235.816 μs | 122.582 μs | 40.360 μs | 24.450 μs | 11.950 μs | 9.240 μs | 83.741 μs | 1.494 ms | 370.453 μs | 55.520 μs |
| combine! vec | Float32 128^3 | 2.816 ms | 17.835 ms | 8.979 ms | 4.746 ms | 660.127 μs | 331.373 μs | 158.542 μs | 120.451 μs | — | — | 661.005 μs | 183.342 μs |
| combine! vec | Float32 256^3 | 26.999 ms | 144.556 ms | 72.271 ms | 37.146 ms | 13.691 ms | 13.935 ms | 13.585 ms | 13.971 ms | — | — | 3.456 ms | 1.018 ms |
| combine! vec | Float32 512^3 | — | — | — | — | 115.790 ms | 108.965 ms | 109.700 ms | 111.482 ms | — | — | — | — |
| combine! vec | Float32 64^3 | 129.781 μs | 2.217 ms | 1.120 ms | 574.521 μs | 65.570 μs | 39.021 μs | 20.381 μs | 14.700 μs | — | — | 335.255 μs | 63.670 μs |
| combine! vec | Float64 128^3 | 6.332 ms | 17.801 ms | 9.019 ms | 5.673 ms | 2.239 ms | 1.887 ms | 1.548 ms | 1.504 ms | — | — | 811.828 μs | 244.243 μs |
| combine! vec | Float64 256^3 | 53.973 ms | 145.694 ms | 73.271 ms | 47.019 ms | 28.627 ms | 26.813 ms | 26.989 ms | 27.245 ms | — | — | 4.040 ms | 1.583 ms |
| combine! vec | Float64 512^3 | — | — | — | — | 231.380 ms | 219.425 ms | 219.133 ms | 221.982 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 281.069 μs | 2.253 ms | 1.127 ms | 584.981 μs | 122.631 μs | 68.160 μs | 34.361 μs | 28.070 μs | — | — | 339.757 μs | 64.941 μs |
| cross! | Float32 128^3 | 4.928 ms | 16.678 ms | 8.579 ms | 4.349 ms | 1.923 ms | 977.220 μs | 491.115 μs | 263.612 μs | 1.223 ms | 3.445 ms | 741.028 μs | 133.602 μs |
| cross! | Float32 256^3 | 44.645 ms | 136.328 ms | 68.726 ms | 36.464 ms | 25.813 ms | 16.513 ms | 12.541 ms | 12.583 ms | — | 14.690 ms | 3.372 ms | 822.829 μs |
| cross! | Float32 512^3 | — | — | — | — | 188.003 ms | 121.172 ms | 110.450 ms | 111.119 ms | — | — | — | — |
| cross! | Float32 64^3 | 430.613 μs | 2.102 ms | 1.060 ms | 544.918 μs | 224.502 μs | 117.431 μs | 59.161 μs | 32.521 μs | 219.582 μs | 1.665 ms | 194.002 μs | 57.391 μs |
| cross! | Float64 128^3 | 10.318 ms | 16.153 ms | 9.063 ms | 8.561 ms | 3.826 ms | 2.306 ms | 1.547 ms | 1.473 ms | 1.263 ms | 2.603 ms | 799.815 μs | 246.643 μs |
| cross! | Float64 256^3 | 87.542 ms | 135.657 ms | 78.456 ms | 71.364 ms | 45.453 ms | 29.030 ms | 27.392 ms | 27.426 ms | — | 15.625 ms | 3.951 ms | 1.593 ms |
| cross! | Float64 512^3 | — | — | — | — | 298.099 ms | 228.886 ms | 220.800 ms | 222.293 ms | — | — | — | — |
| cross! | Float64 64^3 | 477.981 μs | 1.969 ms | 1.025 ms | 527.981 μs | 225.042 μs | 116.151 μs | 64.561 μs | 35.930 μs | 216.592 μs | 1.846 ms | 359.561 μs | 62.771 μs |
| det! tensor | Float32 128^3 | 10.987 ms | 13.761 ms | 7.122 ms | 3.557 ms | 2.239 ms | 1.101 ms | 548.306 μs | 299.183 μs | — | — | 611.298 μs | 184.122 μs |
| det! tensor | Float32 256^3 | 93.250 ms | 114.377 ms | 57.806 ms | 30.451 ms | 27.807 ms | 18.636 ms | 12.097 ms | 12.013 ms | — | — | 2.725 ms | 908.391 μs |
| det! tensor | Float32 512^3 | — | — | — | — | 200.939 ms | 124.801 ms | 104.149 ms | 103.596 ms | — | — | — | — |
| det! tensor | Float32 64^3 | 1.297 ms | 1.715 ms | 858.108 μs | 443.314 μs | 250.532 μs | 137.281 μs | 65.151 μs | 37.191 μs | — | — | 343.669 μs | 63.821 μs |
| det! tensor | Float64 128^3 | 11.869 ms | 14.164 ms | 7.146 ms | 5.213 ms | 3.985 ms | 2.439 ms | 1.672 ms | 1.625 ms | — | — | 863.681 μs | 270.074 μs |
| det! tensor | Float64 256^3 | 96.261 ms | 114.937 ms | 60.442 ms | 46.605 ms | 41.250 ms | 28.845 ms | 25.659 ms | 26.451 ms | — | — | 3.670 ms | 1.786 ms |
| det! tensor | Float64 512^3 | — | — | — | — | 381.984 ms | 239.026 ms | 206.983 ms | 207.743 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 1.370 ms | 1.700 ms | 876.781 μs | 448.779 μs | 252.803 μs | 129.602 μs | 66.360 μs | 42.080 μs | — | — | 363.869 μs | 72.870 μs |
| dot! vec.vec | Float32 128^3 | 2.845 ms | 6.781 ms | 3.477 ms | 1.797 ms | 2.464 ms | 1.254 ms | 624.637 μs | 323.563 μs | 538.855 μs | 2.430 ms | 428.856 μs | 113.921 μs |
| dot! vec.vec | Float32 256^3 | 24.880 ms | 54.576 ms | 28.409 ms | 16.191 ms | 30.274 ms | 13.136 ms | 8.198 ms | 8.119 ms | — | 9.651 ms | 1.580 ms | 634.637 μs |
| dot! vec.vec | Float32 512^3 | — | — | — | — | 196.402 ms | 97.485 ms | 75.424 ms | 75.268 ms | — | — | — | — |
| dot! vec.vec | Float32 64^3 | 335.576 μs | 853.337 μs | 424.365 μs | 222.250 μs | 310.243 μs | 159.971 μs | 81.201 μs | 44.461 μs | 112.901 μs | 1.663 ms | 303.591 μs | 60.341 μs |
| dot! vec.vec | Float64 128^3 | 4.571 ms | 6.749 ms | 3.730 ms | 3.376 ms | 3.440 ms | 1.737 ms | 886.270 μs | 573.165 μs | 618.906 μs | 2.505 ms | 533.841 μs | 204.243 μs |
| dot! vec.vec | Float64 256^3 | 42.263 ms | 56.172 ms | 33.798 ms | 31.532 ms | 36.264 ms | 22.504 ms | 18.471 ms | 19.748 ms | — | 9.784 ms | 2.043 ms | 1.207 ms |
| dot! vec.vec | Float64 512^3 | — | — | — | — | 226.381 ms | 154.071 ms | 149.076 ms | 159.028 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 342.211 μs | 852.801 μs | 428.310 μs | 220.958 μs | 317.663 μs | 159.571 μs | 81.361 μs | 44.610 μs | 127.611 μs | 1.656 ms | 162.125 μs | 59.821 μs |
| mul! tensor.vec | Float32 128^3 | 9.135 ms | 21.169 ms | 10.910 ms | 5.677 ms | 3.491 ms | 1.826 ms | 991.371 μs | 771.778 μs | 1.525 ms | 4.295 ms | 918.199 μs | 208.463 μs |
| mul! tensor.vec | Float32 256^3 | 79.033 ms | 171.834 ms | 87.930 ms | 50.881 ms | 43.068 ms | 29.483 ms | 22.109 ms | 22.008 ms | — | 16.892 ms | 4.152 ms | 1.324 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | 348.899 ms | 222.471 ms | 175.333 ms | 174.454 ms | — | — | — | — |
| mul! tensor.vec | Float32 64^3 | 1.011 ms | 2.628 ms | 1.330 ms | 686.859 μs | 372.223 μs | 214.202 μs | 107.522 μs | 59.561 μs | 255.702 μs | 1.882 ms | 320.574 μs | 67.100 μs |
| mul! tensor.vec | Float64 128^3 | 15.002 ms | 21.129 ms | 12.108 ms | 11.257 ms | 7.061 ms | 5.383 ms | 4.449 ms | 4.256 ms | 1.748 ms | 4.757 ms | 982.624 μs | 371.575 μs |
| mul! tensor.vec | Float64 256^3 | 124.860 ms | 175.649 ms | 102.925 ms | 95.531 ms | 57.713 ms | 51.357 ms | 44.307 ms | 43.405 ms | — | 17.818 ms | 5.402 ms | 2.557 ms |
| mul! tensor.vec | Float64 512^3 | — | — | — | — | 533.991 ms | 378.774 ms | 343.129 ms | 346.282 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 1.182 ms | 2.558 ms | 1.329 ms | 699.429 μs | 377.524 μs | 214.582 μs | 109.421 μs | 59.290 μs | 280.183 μs | 1.951 ms | 449.785 μs | 74.541 μs |
| norm! vec | Float32 128^3 | 769.840 μs | 4.963 ms | 2.529 ms | 1.296 ms | 225.323 μs | 116.271 μs | 62.990 μs | 51.760 μs | 411.304 μs | 2.110 ms | 398.094 μs | 86.131 μs |
| norm! vec | Float32 256^3 | 10.942 ms | 39.879 ms | 20.810 ms | 10.577 ms | 5.301 ms | 4.295 ms | 4.091 ms | 4.249 ms | — | 7.304 ms | 1.216 ms | 386.525 μs |
| norm! vec | Float32 512^3 | — | — | — | — | 52.653 ms | 44.996 ms | 46.122 ms | 46.517 ms | — | — | — | — |
| norm! vec | Float32 64^3 | 56.961 μs | 621.762 μs | 313.206 μs | 161.352 μs | 27.400 μs | 20.980 μs | 12.611 μs | 11.580 μs | 100.251 μs | 1.526 ms | 293.826 μs | 58.990 μs |
| norm! vec | Float64 128^3 | 2.262 ms | 5.010 ms | 2.563 ms | 1.782 ms | 487.265 μs | 254.962 μs | 130.682 μs | 101.921 μs | 463.344 μs | 1.434 ms | 594.819 μs | 173.042 μs |
| norm! vec | Float64 256^3 | 22.598 ms | 41.441 ms | 22.175 ms | 19.803 ms | 11.920 ms | 10.274 ms | 10.248 ms | 10.503 ms | — | 9.850 ms | 2.466 ms | 724.359 μs |
| norm! vec | Float64 512^3 | — | — | — | — | 97.639 ms | 90.073 ms | 91.357 ms | 92.839 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 160.955 μs | 628.865 μs | 321.851 μs | 167.630 μs | 56.440 μs | 35.150 μs | 21.090 μs | 15.800 μs | 101.231 μs | 1.681 ms | 330.640 μs | 60.290 μs |
| tr! tensor | Float32 128^3 | 770.255 μs | 4.438 ms | 2.249 ms | 1.167 ms | 214.702 μs | 113.151 μs | 59.821 μs | 50.380 μs | — | — | 381.081 μs | 85.431 μs |
| tr! tensor | Float32 256^3 | 10.961 ms | 36.969 ms | 18.241 ms | 10.382 ms | 5.147 ms | 4.460 ms | 4.285 ms | 4.361 ms | — | — | 1.214 ms | 394.344 μs |
| tr! tensor | Float32 512^3 | — | — | — | — | 51.458 ms | 45.117 ms | 46.267 ms | 46.860 ms | — | — | — | — |
| tr! tensor | Float32 64^3 | 53.848 μs | 559.549 μs | 281.380 μs | 145.533 μs | 27.490 μs | 18.600 μs | 10.840 μs | 9.390 μs | — | — | 301.965 μs | 68.110 μs |
| tr! tensor | Float64 128^3 | 2.239 ms | 4.366 ms | 2.258 ms | 1.758 ms | 457.195 μs | 239.273 μs | 131.402 μs | 101.801 μs | — | — | 441.365 μs | 119.872 μs |
| tr! tensor | Float64 256^3 | 22.145 ms | 36.362 ms | 20.738 ms | 19.678 ms | 11.735 ms | 10.586 ms | 10.531 ms | 10.762 ms | — | — | 1.340 ms | 727.419 μs |
| tr! tensor | Float64 512^3 | — | — | — | — | 95.574 ms | 91.160 ms | 92.651 ms | 93.818 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 107.309 μs | 550.708 μs | 276.150 μs | 145.507 μs | 53.730 μs | 32.540 μs | 18.760 μs | 13.670 μs | — | — | 315.126 μs | 58.041 μs |

## operators

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.332 ms | 9.191 ms | 4.550 ms | 2.400 ms | 3.203 ms | 1.652 ms | 834.190 μs | 422.744 μs | 697.807 μs | 2.544 ms | 551.324 μs | 90.972 μs |
| curl! vec->vec | Float32 256^3 | 43.101 ms | 72.367 ms | 36.899 ms | 25.627 ms | 27.208 ms | 13.422 ms | 8.555 ms | 8.571 ms | — | 10.865 ms | 1.982 ms | 587.487 μs |
| curl! vec->vec | Float32 512^3 | — | — | — | — | 210.958 ms | 112.992 ms | 81.970 ms | 83.550 ms | — | — | — | — |
| curl! vec->vec | Float32 64^3 | 644.070 μs | 1.158 ms | 585.317 μs | 310.884 μs | 424.824 μs | 218.492 μs | 110.472 μs | 59.210 μs | 182.902 μs | 1.646 ms | 174.757 μs | 56.251 μs |
| curl! vec->vec | Float64 128^3 | 6.542 ms | 9.174 ms | 5.281 ms | 4.185 ms | 3.672 ms | 1.858 ms | 987.181 μs | 519.585 μs | 824.588 μs | 3.153 ms | 750.075 μs | 198.083 μs |
| curl! vec->vec | Float64 256^3 | 58.089 ms | 73.095 ms | 49.179 ms | 40.722 ms | 33.268 ms | 20.453 ms | 19.332 ms | 21.030 ms | — | 13.647 ms | 3.489 ms | 1.133 ms |
| curl! vec->vec | Float64 512^3 | — | — | — | — | 246.925 ms | 166.374 ms | 162.480 ms | 165.773 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 524.406 μs | 1.127 ms | 582.203 μs | 304.882 μs | 461.274 μs | 228.373 μs | 118.061 μs | 61.670 μs | 186.242 μs | 1.786 ms | 393.548 μs | 77.961 μs |
| divergence! vec->scalar | Float32 128^3 | 3.662 ms | 3.649 ms | 1.890 ms | 993.554 μs | 3.362 ms | 1.110 ms | 557.826 μs | 290.203 μs | 326.353 μs | 1.957 ms | 400.152 μs | 86.281 μs |
| divergence! vec->scalar | Float32 256^3 | 28.920 ms | 29.850 ms | 15.081 ms | 9.627 ms | 26.590 ms | 8.842 ms | 4.512 ms | 4.162 ms | — | 5.523 ms | 1.230 ms | 397.924 μs |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | 210.847 ms | 70.642 ms | 46.211 ms | 46.802 ms | — | — | — | — |
| divergence! vec->scalar | Float32 64^3 | 427.458 μs | 465.493 μs | 239.116 μs | 125.776 μs | 434.375 μs | 152.381 μs | 77.560 μs | 42.480 μs | 93.900 μs | 1.537 ms | 325.554 μs | 61.260 μs |
| divergence! vec->scalar | Float64 128^3 | 3.676 ms | 3.697 ms | 2.077 ms | 1.800 ms | 3.343 ms | 1.061 ms | 536.196 μs | 280.153 μs | 407.644 μs | 2.306 ms | 448.700 μs | 134.092 μs |
| divergence! vec->scalar | Float64 256^3 | 32.844 ms | 31.194 ms | 21.140 ms | 19.566 ms | 26.897 ms | 11.138 ms | 10.552 ms | 10.280 ms | — | 7.090 ms | 1.844 ms | 743.438 μs |
| divergence! vec->scalar | Float64 512^3 | — | — | — | — | 217.286 ms | 93.090 ms | 92.310 ms | 92.951 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 415.329 μs | 468.003 μs | 235.837 μs | 123.143 μs | 447.795 μs | 138.812 μs | 74.881 μs | 39.560 μs | 103.111 μs | 344.869 μs | 324.934 μs | 67.200 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.623 ms | 4.665 ms | 2.354 ms | 1.231 ms | 3.732 ms | 1.324 ms | 672.238 μs | 349.114 μs | — | — | 546.243 μs | 89.511 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 35.646 ms | 37.462 ms | 19.009 ms | 11.723 ms | 29.536 ms | 10.427 ms | 5.530 ms | 5.494 ms | — | — | 1.092 ms | 480.555 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | — | — | — | — | 234.985 ms | 82.548 ms | 56.267 ms | 56.685 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 550.278 μs | 583.344 μs | 297.431 μs | 156.406 μs | 484.015 μs | 181.432 μs | 94.191 μs | 53.381 μs | — | — | 283.459 μs | 66.290 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.807 ms | 4.621 ms | 2.647 ms | 2.353 ms | 3.563 ms | 1.341 ms | 670.287 μs | 369.273 μs | — | — | 608.926 μs | 191.013 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 40.931 ms | 38.067 ms | 25.245 ms | 23.779 ms | 29.570 ms | 13.820 ms | 12.977 ms | 12.922 ms | — | — | 2.117 ms | 909.931 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | — | — | — | — | 233.905 ms | 114.432 ms | 111.909 ms | 112.783 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 552.953 μs | 582.643 μs | 301.498 μs | 156.491 μs | 489.355 μs | 176.832 μs | 94.431 μs | 52.481 μs | — | — | 153.083 μs | 71.931 μs |
| gradient! scalar->vec | Float32 128^3 | 3.878 ms | 6.343 ms | 3.184 ms | 1.645 ms | 1.960 ms | 973.459 μs | 488.995 μs | 252.522 μs | 560.525 μs | 2.377 ms | 437.501 μs | 82.271 μs |
| gradient! scalar->vec | Float32 256^3 | 32.209 ms | 49.818 ms | 25.284 ms | 18.636 ms | 15.888 ms | 7.836 ms | 5.697 ms | 5.643 ms | — | 7.929 ms | 1.627 ms | 438.575 μs |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | 125.589 ms | 65.702 ms | 63.720 ms | 64.254 ms | — | — | — | — |
| gradient! scalar->vec | Float32 64^3 | 482.604 μs | 792.999 μs | 408.421 μs | 217.904 μs | 248.053 μs | 126.611 μs | 63.961 μs | 35.120 μs | 133.261 μs | 1.681 ms | 361.502 μs | 75.260 μs |
| gradient! scalar->vec | Float64 128^3 | 4.097 ms | 6.177 ms | 3.420 ms | 2.271 ms | 2.064 ms | 991.759 μs | 497.046 μs | 254.142 μs | 605.225 μs | 2.717 ms | 678.031 μs | 175.883 μs |
| gradient! scalar->vec | Float64 256^3 | 41.972 ms | 50.278 ms | 33.673 ms | 27.350 ms | 20.172 ms | 14.834 ms | 14.018 ms | 14.127 ms | — | 10.338 ms | 2.694 ms | 800.889 μs |
| gradient! scalar->vec | Float64 512^3 | — | — | — | — | 157.261 ms | 128.770 ms | 126.854 ms | 128.109 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 372.986 μs | 803.740 μs | 402.820 μs | 216.375 μs | 259.643 μs | 127.001 μs | 64.581 μs | 34.380 μs | 153.172 μs | 1.872 ms | 375.405 μs | 78.281 μs |
| helmholtz! vec->vec | Float32 128^3 | 5.347 ms | 2.685 ms | 1.515 ms | 1.301 ms | 4.520 ms | 2.291 ms | 1.150 ms | 584.275 μs | 1.480 ms | 4.174 ms | 208.114 μs | 96.641 μs |
| helmholtz! vec->vec | Float32 256^3 | 43.018 ms | 22.153 ms | 18.285 ms | 17.934 ms | 36.298 ms | 18.200 ms | 9.313 ms | 8.586 ms | — | 16.637 ms | 1.071 ms | 590.487 μs |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | 281.602 ms | 146.058 ms | 82.927 ms | 83.822 ms | — | — | — | — |
| helmholtz! vec->vec | Float32 64^3 | 709.122 μs | 357.658 μs | 187.864 μs | 99.692 μs | 616.166 μs | 313.054 μs | 159.182 μs | 83.171 μs | 286.333 μs | 1.935 ms | 321.721 μs | 60.861 μs |
| helmholtz! vec->vec | Float64 128^3 | 6.186 ms | 4.285 ms | 3.888 ms | 3.745 ms | 5.218 ms | 2.634 ms | 1.351 ms | 681.376 μs | 1.802 ms | 5.921 ms | 681.569 μs | 232.383 μs |
| helmholtz! vec->vec | Float64 256^3 | 52.605 ms | 39.695 ms | 36.920 ms | 35.988 ms | 45.605 ms | 23.292 ms | 19.540 ms | 19.657 ms | — | 18.240 ms | 2.817 ms | 1.322 ms |
| helmholtz! vec->vec | Float64 512^3 | — | — | — | — | 347.765 ms | 194.912 ms | 163.393 ms | 167.703 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 785.322 μs | 395.868 μs | 200.525 μs | 109.877 μs | 716.778 μs | 360.424 μs | 184.241 μs | 94.291 μs | 342.613 μs | 2.260 ms | 381.048 μs | 84.351 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 6.384 ms | 3.279 ms | 1.877 ms | 1.682 ms | 5.097 ms | 2.585 ms | 1.289 ms | 660.896 μs | — | — | 206.405 μs | 119.671 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 51.203 ms | 26.002 ms | 20.246 ms | 19.805 ms | 42.087 ms | 20.950 ms | 10.599 ms | 10.002 ms | — | — | 969.713 μs | 671.968 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | — | — | — | — | 325.709 ms | 171.093 ms | 93.646 ms | 93.578 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 840.993 μs | 434.448 μs | 222.258 μs | 115.997 μs | 687.207 μs | 349.564 μs | 174.953 μs | 91.271 μs | — | — | 346.382 μs | 67.620 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 7.169 ms | 4.962 ms | 4.484 ms | 4.381 ms | 5.944 ms | 2.987 ms | 1.540 ms | 815.547 μs | — | — | 814.421 μs | 308.384 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 60.187 ms | 43.988 ms | 40.900 ms | 39.777 ms | 53.046 ms | 27.835 ms | 22.220 ms | 23.509 ms | — | — | 3.617 ms | 1.695 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | — | — | — | — | 398.066 ms | 229.465 ms | 183.852 ms | 187.381 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 933.104 μs | 462.957 μs | 236.175 μs | 124.703 μs | 776.868 μs | 394.494 μs | 199.152 μs | 102.681 μs | — | — | 374.563 μs | 93.280 μs |
| laplacian! scalar | Float32 128^3 | 2.061 ms | 2.746 ms | 1.352 ms | 721.537 μs | 2.150 ms | 492.446 μs | 249.742 μs | 129.942 μs | 265.103 μs | 1.910 ms | 357.451 μs | 82.041 μs |
| laplacian! scalar | Float32 256^3 | 16.755 ms | 22.106 ms | 11.152 ms | 6.085 ms | 17.081 ms | 3.885 ms | 1.952 ms | 1.196 ms | — | 5.490 ms | 946.817 μs | 253.963 μs |
| laplacian! scalar | Float32 512^3 | — | — | — | — | 136.423 ms | 31.716 ms | 26.141 ms | 27.582 ms | — | — | — | — |
| laplacian! scalar | Float32 64^3 | 252.574 μs | 346.110 μs | 176.807 μs | 93.179 μs | 274.853 μs | 69.130 μs | 36.331 μs | 22.130 μs | 83.431 μs | 1.563 ms | 125.781 μs | 52.001 μs |
| laplacian! scalar | Float64 128^3 | 2.114 ms | 2.769 ms | 1.409 ms | 730.468 μs | 2.202 ms | 527.195 μs | 267.723 μs | 140.342 μs | 278.082 μs | 1.957 ms | 361.040 μs | 77.931 μs |
| laplacian! scalar | Float64 256^3 | 17.876 ms | 22.542 ms | 13.154 ms | 10.094 ms | 17.664 ms | 5.236 ms | 4.769 ms | 4.828 ms | — | 4.740 ms | 1.007 ms | 412.744 μs |
| laplacian! scalar | Float64 512^3 | — | — | — | — | 141.317 ms | 54.492 ms | 53.657 ms | 54.940 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 257.704 μs | 346.854 μs | 181.490 μs | 95.390 μs | 282.643 μs | 72.971 μs | 39.710 μs | 23.500 μs | 84.420 μs | 1.586 ms | 311.696 μs | 55.761 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 13.277 ms | 24.177 ms | 12.287 ms | 6.586 ms | 9.580 ms | 4.840 ms | 2.435 ms | 1.236 ms | — | — | 918.561 μs | 218.243 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 105.902 ms | 188.498 ms | 97.058 ms | 71.424 ms | 82.054 ms | 42.823 ms | 25.756 ms | 24.160 ms | — | — | 4.854 ms | 1.196 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | — | — | — | — | 640.245 ms | 346.382 ms | 205.949 ms | 197.696 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.561 ms | 3.069 ms | 1.563 ms | 833.393 μs | 1.215 ms | 624.876 μs | 309.594 μs | 158.022 μs | — | — | 467.259 μs | 69.000 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 18.609 ms | 24.173 ms | 15.134 ms | 11.540 ms | 10.635 ms | 5.734 ms | 3.709 ms | 3.768 ms | — | — | 1.452 ms | 355.604 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 155.770 ms | 192.065 ms | 140.340 ms | 107.575 ms | 90.816 ms | 52.548 ms | 48.753 ms | 49.651 ms | — | — | 8.458 ms | 2.299 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | — | — | — | — | 685.334 ms | 440.168 ms | 387.147 ms | 395.279 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.201 ms | 3.003 ms | 1.552 ms | 822.419 μs | 1.273 ms | 645.096 μs | 323.504 μs | 166.382 μs | — | — | 503.754 μs | 101.521 μs |

## convolution

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.849 ms | 2.252 ms | 1.117 ms | 583.670 μs | 1.361 ms | 300.363 μs | 154.651 μs | 83.421 μs | 296.642 μs | 1.855 ms | 274.024 μs | 134.442 μs |
| assignment_window | Float32 256^3 | 28.203 ms | 24.888 ms | 9.162 ms | 4.771 ms | 18.023 ms | 6.962 ms | 2.102 ms | 2.013 ms | — | 3.952 ms | 906.052 μs | 271.043 μs |
| assignment_window | Float32 512^3 | — | — | — | — | 150.143 ms | 54.426 ms | 32.759 ms | 21.780 ms | — | — | — | — |
| assignment_window | Float32 64^3 | 230.412 μs | 284.137 μs | 145.571 μs | 79.361 μs | 176.112 μs | 44.690 μs | 25.351 μs | 16.840 μs | 138.651 μs | 1.640 ms | 408.218 μs | 127.492 μs |
| assignment_window | Float64 128^3 | 1.923 ms | 2.206 ms | 1.137 ms | 684.038 μs | 1.544 ms | 392.794 μs | 365.324 μs | 321.743 μs | 306.863 μs | 1.901 ms | 456.909 μs | 146.542 μs |
| assignment_window | Float64 256^3 | 42.182 ms | 32.063 ms | 16.713 ms | 9.242 ms | 27.898 ms | 11.831 ms | 7.322 ms | 4.386 ms | — | 4.237 ms | 975.561 μs | 293.573 μs |
| assignment_window | Float64 512^3 | — | — | — | — | 220.058 ms | 92.659 ms | 59.236 ms | 43.545 ms | — | — | — | — |
| assignment_window | Float64 64^3 | 244.355 μs | 282.564 μs | 146.029 μs | 83.786 μs | 199.382 μs | 47.460 μs | 26.710 μs | 17.850 μs | 141.232 μs | 1.542 ms | 221.844 μs | 114.431 μs |
| combine!∘kernel vector | Float32 128^3 | 8.757 ms | 11.414 ms | 5.701 ms | 2.921 ms | 3.149 ms | 1.547 ms | 776.849 μs | 416.964 μs | — | — | 514.875 μs | 133.091 μs |
| combine!∘kernel vector | Float32 256^3 | 70.758 ms | 90.386 ms | 45.671 ms | 24.701 ms | 27.839 ms | 14.121 ms | 9.869 ms | 9.970 ms | — | — | 2.214 ms | 924.721 μs |
| combine!∘kernel vector | Float32 512^3 | — | — | — | — | 241.620 ms | 135.407 ms | 92.212 ms | 93.088 ms | — | — | — | — |
| combine!∘kernel vector | Float32 64^3 | 1.189 ms | 1.416 ms | 720.281 μs | 369.248 μs | 420.404 μs | 207.282 μs | 105.621 μs | 56.570 μs | — | — | 325.364 μs | 78.461 μs |
| combine!∘kernel vector | Float64 128^3 | 10.046 ms | 11.079 ms | 5.966 ms | 5.261 ms | 3.687 ms | 2.052 ms | 1.091 ms | 752.867 μs | — | — | 766.781 μs | 294.554 μs |
| combine!∘kernel vector | Float64 256^3 | 82.613 ms | 91.120 ms | 51.979 ms | 46.381 ms | 34.145 ms | 23.060 ms | 21.962 ms | 23.351 ms | — | — | 3.711 ms | 1.792 ms |
| combine!∘kernel vector | Float64 512^3 | — | — | — | — | 256.016 ms | 186.416 ms | 184.174 ms | 185.285 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 1.196 ms | 1.410 ms | 719.913 μs | 365.096 μs | 378.834 μs | 226.922 μs | 118.331 μs | 63.720 μs | — | — | 353.470 μs | 80.550 μs |
| convolve! scalar | Float32 128^3 | 1.642 ms | 2.071 ms | 1.064 ms | 545.465 μs | 920.419 μs | 108.071 μs | 56.900 μs | 36.420 μs | 220.032 μs | 1.755 ms | 158.468 μs | 63.601 μs |
| convolve! scalar | Float32 256^3 | 13.765 ms | 17.286 ms | 8.580 ms | 7.769 ms | 7.589 ms | 2.883 ms | 2.643 ms | 2.733 ms | — | 3.659 ms | 720.153 μs | 312.854 μs |
| convolve! scalar | Float32 512^3 | — | — | — | — | 62.006 ms | 37.388 ms | 36.530 ms | 36.849 ms | — | — | — | — |
| convolve! scalar | Float32 64^3 | 201.161 μs | 268.019 μs | 135.606 μs | 72.302 μs | 116.741 μs | 16.490 μs | 9.710 μs | 7.580 μs | 78.951 μs | 1.480 ms | 303.195 μs | 57.290 μs |
| convolve! scalar | Float64 128^3 | 1.960 ms | 2.117 ms | 1.319 ms | 996.734 μs | 997.571 μs | 172.471 μs | 93.971 μs | 71.861 μs | 302.553 μs | 1.784 ms | 211.581 μs | 90.291 μs |
| convolve! scalar | Float64 256^3 | 19.251 ms | 18.151 ms | 13.824 ms | 12.228 ms | 10.898 ms | 7.861 ms | 7.617 ms | 7.770 ms | — | 4.442 ms | 1.058 ms | 575.286 μs |
| convolve! scalar | Float64 512^3 | — | — | — | — | 89.577 ms | 73.921 ms | 73.925 ms | 74.184 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 179.774 μs | 260.094 μs | 133.456 μs | 71.629 μs | 128.572 μs | 28.980 μs | 14.080 μs | 10.640 μs | 78.591 μs | 1.618 ms | 337.239 μs | 55.431 μs |
| convolve! vector | Float32 128^3 | 6.067 ms | 9.107 ms | 4.604 ms | 2.378 ms | 2.094 ms | 1.100 ms | 548.955 μs | 299.313 μs | 731.727 μs | 2.557 ms | 472.728 μs | 108.091 μs |
| convolve! vector | Float32 256^3 | 49.271 ms | 71.294 ms | 36.739 ms | 23.820 ms | 20.326 ms | 11.003 ms | 9.834 ms | 9.916 ms | — | 10.821 ms | 1.843 ms | 681.018 μs |
| convolve! vector | Float32 512^3 | — | — | — | — | 177.069 ms | 94.434 ms | 92.113 ms | 92.519 ms | — | — | — | — |
| convolve! vector | Float32 64^3 | 736.726 μs | 1.139 ms | 583.108 μs | 299.989 μs | 272.252 μs | 146.602 μs | 74.590 μs | 40.140 μs | 161.751 μs | 1.595 ms | 314.803 μs | 70.901 μs |
| convolve! vector | Float64 128^3 | 7.164 ms | 9.344 ms | 5.209 ms | 4.338 ms | 2.648 ms | 1.550 ms | 877.130 μs | 748.577 μs | 792.657 μs | 2.910 ms | 640.119 μs | 227.133 μs |
| convolve! vector | Float64 256^3 | 61.696 ms | 76.413 ms | 47.698 ms | 40.195 ms | 30.552 ms | 22.792 ms | 21.925 ms | 23.340 ms | — | 12.297 ms | 2.764 ms | 1.302 ms |
| convolve! vector | Float64 512^3 | — | — | — | — | 223.020 ms | 184.776 ms | 183.563 ms | 184.580 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 704.772 μs | 1.148 ms | 588.441 μs | 303.859 μs | 217.852 μs | 132.852 μs | 72.700 μs | 39.621 μs | 167.451 μs | 1.655 ms | 357.520 μs | 74.220 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.724 ms | 3.924 ms | 2.466 ms | 1.347 ms | 3.815 ms | 1.637 ms | 869.730 μs | 453.674 μs | — | — | 386.470 μs | 73.720 μs |
| exponential_convolve! scalar | Float32 256^3 | 34.753 ms | 24.909 ms | 13.162 ms | 7.389 ms | 28.508 ms | 11.862 ms | 5.970 ms | 3.107 ms | — | — | 846.822 μs | 249.413 μs |
| exponential_convolve! scalar | Float32 512^3 | — | — | — | — | 225.346 ms | 92.580 ms | 46.442 ms | 27.473 ms | — | — | — | — |
| exponential_convolve! scalar | Float32 64^3 | 2.197 ms | 1.310 ms | 698.000 μs | 362.265 μs | 775.658 μs | 345.654 μs | 170.292 μs | 99.191 μs | — | — | 355.701 μs | 62.701 μs |
| exponential_convolve! scalar | Float64 128^3 | 8.246 ms | 5.664 ms | 3.308 ms | 1.972 ms | 5.829 ms | 2.532 ms | 1.271 ms | 659.776 μs | — | — | 452.793 μs | 129.502 μs |
| exponential_convolve! scalar | Float64 256^3 | 56.283 ms | 40.122 ms | 21.475 ms | 12.566 ms | 41.019 ms | 17.691 ms | 9.044 ms | 4.999 ms | — | — | 1.684 ms | 705.918 μs |
| exponential_convolve! scalar | Float64 512^3 | — | — | — | — | 312.730 ms | 134.163 ms | 69.681 ms | 54.731 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 737.673 μs | 563.050 μs | 285.564 μs | 150.037 μs | 700.417 μs | 309.533 μs | 158.721 μs | 84.260 μs | — | — | 332.052 μs | 62.870 μs |
| exponential_convolve! vector | Float32 128^3 | 19.113 ms | 15.232 ms | 8.154 ms | 4.885 ms | 13.386 ms | 6.392 ms | 3.633 ms | 1.713 ms | — | — | 669.992 μs | 134.301 μs |
| exponential_convolve! vector | Float32 256^3 | 118.377 ms | 97.947 ms | 50.681 ms | 26.940 ms | 101.617 ms | 47.162 ms | 23.779 ms | 12.430 ms | — | — | 2.256 ms | 701.227 μs |
| exponential_convolve! vector | Float32 512^3 | — | — | — | — | 833.980 ms | 371.941 ms | 186.136 ms | 97.797 ms | — | — | — | — |
| exponential_convolve! vector | Float32 64^3 | 6.918 ms | 4.417 ms | 2.307 ms | 1.218 ms | 2.259 ms | 1.219 ms | 578.537 μs | 332.853 μs | — | — | 336.138 μs | 75.871 μs |
| exponential_convolve! vector | Float64 128^3 | 27.195 ms | 20.847 ms | 11.051 ms | 6.487 ms | 20.029 ms | 9.076 ms | 4.583 ms | 2.391 ms | — | — | 928.874 μs | 291.874 μs |
| exponential_convolve! vector | Float64 256^3 | 186.872 ms | 146.013 ms | 76.188 ms | 40.859 ms | 144.067 ms | 63.915 ms | 32.981 ms | 19.357 ms | — | — | 4.924 ms | 1.965 ms |
| exponential_convolve! vector | Float64 512^3 | — | — | — | — | 1.111 s | 512.433 ms | 256.095 ms | 164.820 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.535 ms | 2.166 ms | 1.110 ms | 568.887 μs | 2.459 ms | 1.102 ms | 552.615 μs | 283.652 μs | — | — | 429.764 μs | 81.801 μs |
| spectral_band | Float32 128^3 | 4.200 ms | 3.422 ms | 1.715 ms | 886.555 μs | 3.856 ms | 1.365 ms | 686.847 μs | 348.073 μs | 334.154 μs | 2.050 ms | 400.569 μs | 97.391 μs |
| spectral_band | Float32 256^3 | 46.789 ms | 33.835 ms | 13.683 ms | 7.165 ms | 39.014 ms | 15.953 ms | 5.429 ms | 2.741 ms | — | 6.344 ms | 986.036 μs | 269.943 μs |
| spectral_band | Float32 512^3 | — | — | — | — | 314.469 ms | 125.228 ms | 64.896 ms | 32.751 ms | — | — | — | — |
| spectral_band | Float32 64^3 | 523.213 μs | 427.685 μs | 219.260 μs | 116.255 μs | 492.845 μs | 179.682 μs | 92.471 μs | 49.870 μs | 106.071 μs | 1.537 ms | 142.500 μs | 80.151 μs |
| spectral_band | Float64 128^3 | 4.273 ms | 3.403 ms | 1.740 ms | 942.494 μs | 3.969 ms | 1.378 ms | 693.078 μs | 357.014 μs | 361.113 μs | 2.105 ms | 432.997 μs | 107.612 μs |
| spectral_band | Float64 256^3 | 60.189 ms | 41.285 ms | 21.167 ms | 11.444 ms | 48.049 ms | 19.562 ms | 10.115 ms | 4.252 ms | — | 5.611 ms | 1.281 ms | 298.844 μs |
| spectral_band | Float64 512^3 | — | — | — | — | 394.593 ms | 153.201 ms | 79.445 ms | 45.161 ms | — | — | — | — |
| spectral_band | Float64 64^3 | 523.418 μs | 433.651 μs | 221.418 μs | 123.355 μs | 504.155 μs | 181.802 μs | 93.401 μs | 50.370 μs | 110.411 μs | 1.651 ms | 347.331 μs | 69.180 μs |
| spectral_cutoff | Float32 128^3 | 4.207 ms | 3.352 ms | 1.718 ms | 878.672 μs | 3.858 ms | 1.364 ms | 685.208 μs | 349.213 μs | 331.623 μs | 2.046 ms | 404.955 μs | 102.101 μs |
| spectral_cutoff | Float32 256^3 | 46.822 ms | 34.547 ms | 13.809 ms | 7.206 ms | 38.752 ms | 15.905 ms | 5.418 ms | 2.738 ms | — | 5.403 ms | 1.068 ms | 275.163 μs |
| spectral_cutoff | Float32 512^3 | — | — | — | — | 314.255 ms | 125.415 ms | 65.606 ms | 32.848 ms | — | — | — | — |
| spectral_cutoff | Float32 64^3 | 509.374 μs | 427.396 μs | 220.422 μs | 116.163 μs | 491.925 μs | 180.001 μs | 92.501 μs | 49.921 μs | 108.881 μs | 1.625 ms | 322.911 μs | 83.271 μs |
| spectral_cutoff | Float64 128^3 | 4.197 ms | 3.462 ms | 1.738 ms | 974.235 μs | 3.966 ms | 1.379 ms | 693.498 μs | 360.543 μs | 351.793 μs | 2.120 ms | 405.973 μs | 104.231 μs |
| spectral_cutoff | Float64 256^3 | 59.604 ms | 41.886 ms | 21.099 ms | 11.370 ms | 47.658 ms | 19.436 ms | 10.163 ms | 4.213 ms | — | 5.621 ms | 1.287 ms | 300.624 μs |
| spectral_cutoff | Float64 512^3 | — | — | — | — | 391.369 ms | 153.734 ms | 80.140 ms | 45.145 ms | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 534.454 μs | 433.480 μs | 222.257 μs | 118.498 μs | 505.175 μs | 181.792 μs | 94.040 μs | 50.490 μs | 117.711 μs | 1.647 ms | 355.066 μs | 72.781 μs |
| squared_wavenumber_field | Float32 128^3 | 1.841 ms | 2.230 ms | 1.130 ms | 579.126 μs | 1.375 ms | 296.254 μs | 150.622 μs | 79.120 μs | 262.463 μs | 1.824 ms | 354.675 μs | 84.721 μs |
| squared_wavenumber_field | Float32 256^3 | 27.936 ms | 25.131 ms | 9.074 ms | 4.704 ms | 18.199 ms | 7.016 ms | 2.032 ms | 1.675 ms | — | 3.812 ms | 819.707 μs | 221.563 μs |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | 151.875 ms | 54.583 ms | 32.704 ms | 21.584 ms | — | — | — | — |
| squared_wavenumber_field | Float32 64^3 | 228.975 μs | 279.362 μs | 144.217 μs | 77.567 μs | 176.631 μs | 41.950 μs | 22.720 μs | 14.151 μs | 91.321 μs | 1.517 ms | 373.013 μs | 78.972 μs |
| squared_wavenumber_field | Float64 128^3 | 1.940 ms | 2.180 ms | 1.119 ms | 706.287 μs | 1.420 ms | 425.364 μs | 347.304 μs | 323.592 μs | 264.163 μs | 1.805 ms | 396.751 μs | 94.861 μs |
| squared_wavenumber_field | Float64 256^3 | 41.271 ms | 31.606 ms | 16.422 ms | 9.209 ms | 28.059 ms | 11.818 ms | 7.257 ms | 4.368 ms | — | 4.151 ms | 835.978 μs | 252.183 μs |
| squared_wavenumber_field | Float64 512^3 | — | — | — | — | 219.319 ms | 92.814 ms | 59.240 ms | 42.975 ms | — | — | — | — |
| squared_wavenumber_field | Float64 64^3 | 245.685 μs | 283.214 μs | 143.709 μs | 81.335 μs | 182.112 μs | 43.460 μs | 23.890 μs | 14.300 μs | 88.931 μs | 1.612 ms | 323.221 μs | 65.281 μs |
| translation_kernel | Float32 128^3 | 1.841 ms | 2.625 ms | 1.356 ms | 680.137 μs | 1.536 ms | 447.655 μs | 227.083 μs | 118.971 μs | — | — | 394.496 μs | 112.821 μs |
| translation_kernel | Float32 256^3 | 28.357 ms | 27.746 ms | 10.625 ms | 5.481 ms | 19.566 ms | 8.290 ms | 2.117 ms | 2.019 ms | — | — | 856.930 μs | 255.093 μs |
| translation_kernel | Float32 512^3 | — | — | — | — | 167.737 ms | 65.912 ms | 35.321 ms | 23.073 ms | — | — | — | — |
| translation_kernel | Float32 64^3 | 232.572 μs | 329.267 μs | 170.177 μs | 91.174 μs | 197.472 μs | 60.931 μs | 32.780 μs | 20.060 μs | — | — | 342.271 μs | 104.771 μs |
| translation_kernel | Float64 128^3 | 1.833 ms | 2.683 ms | 1.382 ms | 740.848 μs | 1.451 ms | 457.825 μs | 282.373 μs | 324.903 μs | — | — | 453.284 μs | 146.012 μs |
| translation_kernel | Float64 256^3 | 41.397 ms | 34.957 ms | 18.599 ms | 9.924 ms | 28.317 ms | 13.159 ms | 7.687 ms | 4.347 ms | — | — | 1.335 ms | 452.685 μs |
| translation_kernel | Float64 512^3 | — | — | — | — | 218.222 ms | 103.214 ms | 63.170 ms | 44.004 ms | — | — | — | — |
| translation_kernel | Float64 64^3 | 232.803 μs | 344.441 μs | 177.822 μs | 95.455 μs | 187.331 μs | 62.590 μs | 33.550 μs | 20.820 μs | — | — | 424.413 μs | 100.811 μs |

## transfer

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 28.940 ms | 14.161 ms | 7.801 ms | 4.725 ms | 21.115 ms | 11.027 ms | 5.946 ms | 3.423 ms | 2.280 ms | 4.864 ms | 774.794 μs | 202.263 μs |
| anterpolate! CatmullRom | Float32 256^3 | 445.713 ms | 228.844 ms | 123.921 ms | 78.168 ms | 173.277 ms | 88.950 ms | 45.022 ms | 23.951 ms | — | 17.932 ms | 3.198 ms | 2.880 ms |
| anterpolate! CatmullRom | Float32 512^3 | — | — | — | — | 2.943 s | 1.499 s | 783.147 ms | 441.685 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.249 ms | 1.874 ms | 1.208 ms | 913.384 μs | 2.523 ms | 1.450 ms | 932.021 μs | 652.876 μs | 116.972 μs | 2.057 ms | 434.815 μs | 105.992 μs |
| anterpolate! CatmullRom | Float64 128^3 | 34.542 ms | 16.274 ms | 8.112 ms | 4.894 ms | 22.060 ms | 11.591 ms | 6.148 ms | 3.553 ms | 2.691 ms | 4.862 ms | 881.660 μs | 244.363 μs |
| anterpolate! CatmullRom | Float64 256^3 | 552.915 ms | 290.910 ms | 166.179 ms | 117.563 ms | 263.455 ms | 130.406 ms | 67.722 ms | 35.466 ms | — | 19.810 ms | 4.031 ms | 4.666 ms |
| anterpolate! CatmullRom | Float64 512^3 | — | — | — | — | 3.362 s | 1.737 s | 928.917 ms | 515.890 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.425 ms | 1.926 ms | 1.277 ms | 954.485 μs | 2.530 ms | 1.499 ms | 965.789 μs | 695.486 μs | 185.312 μs | 2.004 ms | 356.139 μs | 117.601 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 206.639 ms | 103.232 ms | 53.744 ms | 30.000 ms | 159.887 ms | 80.537 ms | 40.603 ms | 21.680 ms | 12.241 ms | 15.478 ms | 3.480 ms | 983.072 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.514 s | 1.333 s | 796.348 ms | 531.881 ms | 1.286 s | 643.816 ms | 322.030 ms | 164.797 ms | — | 48.567 ms | 17.733 ms | 14.982 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 11.796 s | 5.944 s | 3.081 s | 1.649 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.599 ms | 13.313 ms | 8.357 ms | 5.699 ms | 19.873 ms | 10.618 ms | 6.460 ms | 4.343 ms | 486.825 μs | 5.959 ms | 1.345 ms | 318.094 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 231.324 ms | 111.720 ms | 56.905 ms | 31.151 ms | 160.790 ms | 80.615 ms | 40.562 ms | 21.687 ms | 13.808 ms | 16.564 ms | 4.326 ms | 1.174 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.830 s | 1.540 s | 962.001 ms | 675.882 ms | 1.402 s | 697.115 ms | 354.181 ms | 179.349 ms | — | 66.043 ms | 28.006 ms | 24.239 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 12.795 s | 6.538 s | 3.419 s | 2.083 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 25.461 ms | 13.667 ms | 8.610 ms | 5.857 ms | 19.961 ms | 10.749 ms | 6.590 ms | 4.473 ms | 825.268 μs | 5.503 ms | 1.808 ms | 333.433 μs |
| anterpolate! NUFFT | Float32 128^3 | 453.275 ms | 249.588 ms | 166.972 ms | 126.014 ms | 369.698 ms | 193.018 ms | 110.791 ms | 59.706 ms | 20.177 ms | 18.762 ms | 4.619 ms | 2.762 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.662 s | 2.590 s | 1.613 s | 1.206 s | 3.783 s | 2.000 s | 1.106 s | 671.419 ms | — | 120.799 ms | 32.116 ms | 28.407 ms |
| anterpolate! NUFFT | Float32 512^3 | — | — | — | — | 30.987 s | 16.404 s | 9.048 s | 5.464 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 34.030 ms | 18.389 ms | 11.864 ms | 8.462 ms | 27.190 ms | 14.323 ms | 8.560 ms | 5.852 ms | 1.989 ms | 6.296 ms | 1.556 ms | 431.207 μs |
| anterpolate! NUFFT | Float64 128^3 | 582.314 ms | 366.883 ms | 244.533 ms | 194.140 ms | 424.578 ms | 238.994 ms | 142.939 ms | 89.947 ms | 30.358 ms | 22.503 ms | 9.419 ms | 6.537 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.518 s | 3.190 s | 2.065 s | 1.649 s | 3.659 s | 2.028 s | 1.235 s | 877.546 ms | — | 160.735 ms | 75.186 ms | 58.232 ms |
| anterpolate! NUFFT | Float64 512^3 | — | — | — | — | 39.739 s | 21.890 s | 12.669 s | 8.232 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 41.043 ms | 22.676 ms | 15.325 ms | 11.878 ms | 33.478 ms | 17.894 ms | 10.588 ms | 7.525 ms | 3.892 ms | 8.203 ms | 2.551 ms | 818.608 μs |
| anterpolate! trilinear | Float32 128^3 | 4.622 ms | 2.326 ms | 1.425 ms | 934.458 μs | 4.806 ms | 2.580 ms | 1.442 ms | 862.608 μs | 460.884 μs | 2.018 ms | 399.236 μs | 81.071 μs |
| anterpolate! trilinear | Float32 256^3 | 90.598 ms | 49.168 ms | 28.838 ms | 22.504 ms | 41.580 ms | 21.844 ms | 11.651 ms | 6.722 ms | — | 6.631 ms | 935.853 μs | 730.828 μs |
| anterpolate! trilinear | Float32 512^3 | — | — | — | — | 737.978 ms | 379.590 ms | 202.481 ms | 117.586 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 495.629 μs | 323.836 μs | 226.273 μs | 176.552 μs | 370.024 μs | 229.472 μs | 174.322 μs | 126.051 μs | 70.080 μs | 1.565 ms | 307.708 μs | 78.742 μs |
| anterpolate! trilinear | Float64 128^3 | 5.575 ms | 2.810 ms | 1.660 ms | 1.144 ms | 6.319 ms | 3.294 ms | 1.858 ms | 1.168 ms | 596.666 μs | 1.980 ms | 394.307 μs | 98.471 μs |
| anterpolate! trilinear | Float64 256^3 | 98.538 ms | 56.188 ms | 38.006 ms | 30.037 ms | 71.912 ms | 36.546 ms | 19.701 ms | 11.100 ms | — | 6.838 ms | 986.761 μs | 1.111 ms |
| anterpolate! trilinear | Float64 512^3 | — | — | — | — | 778.642 ms | 411.449 ms | 221.082 ms | 126.073 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 519.589 μs | 362.857 μs | 268.310 μs | 211.923 μs | 379.594 μs | 240.113 μs | 178.542 μs | 133.851 μs | 83.721 μs | 1.554 ms | 319.743 μs | 79.841 μs |
| interpolate! CatmullRom | Float32 128^3 | 12.089 ms | 5.951 ms | 3.108 ms | 1.684 ms | 5.461 ms | 2.795 ms | 1.387 ms | 735.726 μs | 972.889 μs | 3.140 ms | 513.046 μs | 122.371 μs |
| interpolate! CatmullRom | Float32 256^3 | 302.879 ms | 156.419 ms | 83.584 ms | 53.267 ms | 53.624 ms | 28.340 ms | 13.501 ms | 7.328 ms | — | 14.577 ms | 1.580 ms | 867.350 μs |
| interpolate! CatmullRom | Float32 512^3 | — | — | — | — | 1.815 s | 926.248 ms | 471.745 ms | 267.260 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.336 ms | 711.866 μs | 437.869 μs | 300.388 μs | 626.226 μs | 330.353 μs | 201.532 μs | 134.252 μs | 101.321 μs | 1.724 ms | 376.135 μs | 84.421 μs |
| interpolate! CatmullRom | Float64 128^3 | 16.595 ms | 7.290 ms | 3.708 ms | 2.001 ms | 5.713 ms | 2.877 ms | 1.445 ms | 776.637 μs | 1.411 ms | 2.789 ms | 665.788 μs | 195.203 μs |
| interpolate! CatmullRom | Float64 256^3 | 330.742 ms | 173.228 ms | 101.047 ms | 66.240 ms | 154.507 ms | 71.476 ms | 37.723 ms | 19.711 ms | — | 12.939 ms | 2.020 ms | 1.713 ms |
| interpolate! CatmullRom | Float64 512^3 | — | — | — | — | 2.074 s | 1.061 s | 556.414 ms | 296.880 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.386 ms | 755.180 μs | 461.670 μs | 321.818 μs | 676.297 μs | 359.374 μs | 215.892 μs | 144.661 μs | 166.201 μs | 1.759 ms | 432.806 μs | 112.201 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 77.538 ms | 38.641 ms | 19.795 ms | 10.740 ms | 42.455 ms | 21.422 ms | 10.746 ms | 5.648 ms | 5.370 ms | 14.027 ms | 2.087 ms | 465.615 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.640 s | 901.758 ms | 561.171 ms | 355.760 ms | 364.130 ms | 174.392 ms | 89.482 ms | 47.681 ms | — | 30.216 ms | 10.730 ms | 4.708 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 5.496 s | 2.855 s | 1.532 s | 901.570 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.968 ms | 4.733 ms | 2.883 ms | 1.938 ms | 5.124 ms | 2.694 ms | 1.624 ms | 1.083 ms | 688.416 μs | 3.166 ms | 1.072 ms | 270.574 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 98.748 ms | 47.842 ms | 24.998 ms | 13.674 ms | 41.617 ms | 20.883 ms | 10.525 ms | 5.541 ms | 8.105 ms | 9.517 ms | 2.329 ms | 841.871 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.991 s | 1.134 s | 751.721 ms | 481.652 ms | 584.434 ms | 284.101 ms | 152.613 ms | 74.127 ms | — | 28.103 ms | 10.354 ms | 10.000 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 6.814 s | 3.566 s | 2.080 s | 1.155 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.170 ms | 4.977 ms | 2.998 ms | 2.024 ms | 5.286 ms | 2.834 ms | 1.672 ms | 1.117 ms | 911.428 μs | 3.595 ms | 1.429 ms | 318.544 μs |
| interpolate! NUFFT | Float32 128^3 | 347.500 ms | 203.706 ms | 137.004 ms | 112.535 ms | 254.596 ms | 132.080 ms | 83.941 ms | 45.631 ms | 12.723 ms | 16.422 ms | 3.783 ms | 1.884 ms |
| interpolate! NUFFT | Float32 256^3 | 3.874 s | 2.238 s | 1.475 s | 1.063 s | 2.981 s | 1.616 s | 940.693 ms | 610.125 ms | — | 72.243 ms | 25.429 ms | 17.610 ms |
| interpolate! NUFFT | Float32 512^3 | — | — | — | — | 24.553 s | 13.330 s | 7.683 s | 4.937 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 18.087 ms | 10.580 ms | 7.136 ms | 5.312 ms | 12.092 ms | 6.569 ms | 3.743 ms | 2.426 ms | 1.847 ms | 4.302 ms | 1.350 ms | 413.776 μs |
| interpolate! NUFFT | Float64 128^3 | 452.141 ms | 284.231 ms | 214.567 ms | 176.271 ms | 221.869 ms | 138.955 ms | 94.695 ms | 64.989 ms | 25.361 ms | 18.237 ms | 8.028 ms | 5.538 ms |
| interpolate! NUFFT | Float64 256^3 | 4.263 s | 2.553 s | 1.814 s | 1.465 s | 2.040 s | 1.248 s | 867.055 ms | 717.217 ms | — | 118.516 ms | 55.024 ms | 47.705 ms |
| interpolate! NUFFT | Float64 512^3 | — | — | — | — | 24.856 s | 14.191 s | 8.687 s | 9.380 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 24.593 ms | 15.853 ms | 11.858 ms | 9.597 ms | 17.907 ms | 9.885 ms | 6.068 ms | 4.102 ms | 3.417 ms | 6.116 ms | 2.315 ms | 930.659 μs |
| interpolate! trilinear | Float32 128^3 | 2.029 ms | 1.050 ms | 549.552 μs | 296.572 μs | 1.305 ms | 689.897 μs | 337.193 μs | 179.602 μs | 255.582 μs | 1.719 ms | 366.430 μs | 64.600 μs |
| interpolate! trilinear | Float32 256^3 | 59.612 ms | 31.528 ms | 16.597 ms | 10.000 ms | 13.998 ms | 7.523 ms | 3.437 ms | 1.871 ms | — | 3.594 ms | 535.992 μs | 251.003 μs |
| interpolate! trilinear | Float32 512^3 | — | — | — | — | 430.979 ms | 218.136 ms | 121.634 ms | 61.471 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 234.257 μs | 128.294 μs | 80.945 μs | 56.025 μs | 149.611 μs | 79.281 μs | 47.590 μs | 33.240 μs | 65.160 μs | 1.448 ms | 312.795 μs | 61.161 μs |
| interpolate! trilinear | Float64 128^3 | 2.641 ms | 1.283 ms | 657.885 μs | 363.000 μs | 1.356 ms | 709.787 μs | 349.534 μs | 189.212 μs | 325.503 μs | 1.772 ms | 336.686 μs | 95.381 μs |
| interpolate! trilinear | Float64 256^3 | 64.721 ms | 35.808 ms | 22.236 ms | 14.456 ms | 33.796 ms | 16.799 ms | 8.218 ms | 4.202 ms | — | 4.014 ms | 845.229 μs | 403.745 μs |
| interpolate! trilinear | Float64 512^3 | — | — | — | — | 442.762 ms | 233.803 ms | 125.512 ms | 63.333 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 244.280 μs | 135.084 μs | 83.822 μs | 58.437 μs | 163.782 μs | 86.521 μs | 50.200 μs | 33.651 μs | 65.930 μs | 1.530 ms | 155.672 μs | 65.070 μs |

## reductions

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.263 ms | 7.083 ms | 7.566 ms | 7.786 ms | 6.963 ms | 4.943 ms | 5.829 ms | 6.063 ms | 2.099 ms | 27.761 ms | 839.031 μs | 302.463 μs |
| co-spectrum vec.vec | Float32 256^3 | 66.852 ms | 49.480 ms | 45.365 ms | 42.410 ms | 55.712 ms | 37.209 ms | 31.618 ms | 29.649 ms | — | 97.666 ms | 2.655 ms | 948.830 μs |
| co-spectrum vec.vec | Float32 512^3 | — | — | — | — | 440.773 ms | 272.325 ms | 189.961 ms | 152.090 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.076 ms | 1.308 ms | 1.519 ms | 1.587 ms | 904.859 μs | 941.690 μs | 1.214 ms | 1.343 ms | 491.824 μs | 17.761 ms | 588.948 μs | 192.883 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.678 ms | 6.316 ms | 5.875 ms | 5.423 ms | 7.257 ms | 5.184 ms | 4.713 ms | 4.477 ms | 2.194 ms | 29.708 ms | 28.650 ms | 374.955 μs |
| co-spectrum vec.vec | Float64 256^3 | 70.996 ms | 50.569 ms | 37.153 ms | 30.218 ms | 58.555 ms | 37.312 ms | 28.203 ms | 22.565 ms | — | 109.563 ms | 65.238 ms | 1.380 ms |
| co-spectrum vec.vec | Float64 512^3 | — | — | — | — | 462.419 ms | 285.279 ms | 178.714 ms | 128.927 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.090 ms | 953.007 μs | 917.569 μs | 1.012 ms | 944.150 μs | 740.978 μs | 886.121 μs | 937.238 μs | 482.135 μs | 16.075 ms | 14.991 ms | 184.602 μs |
| cross-correlation vec.vec | Float32 128^3 | 43.424 ms | 41.255 ms | 37.979 ms | 37.074 ms | 38.354 ms | 29.434 ms | 23.722 ms | 22.109 ms | 5.891 ms | 43.640 ms | 1.660 ms | 660.748 μs |
| cross-correlation vec.vec | Float32 256^3 | 639.849 ms | 502.028 ms | 357.431 ms | 295.912 ms | 802.665 ms | 560.674 ms | 329.799 ms | 260.625 ms | — | 186.915 ms | 9.711 ms | 5.817 ms |
| cross-correlation vec.vec | Float32 512^3 | — | — | — | — | 8.021 s | 5.503 s | 2.976 s | 2.190 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.909 ms | 6.487 ms | 6.293 ms | 6.488 ms | 3.991 ms | 3.771 ms | 3.875 ms | 3.739 ms | 1.025 ms | 20.682 ms | 639.508 μs | 263.693 μs |
| cross-correlation vec.vec | Float64 128^3 | 86.193 ms | 68.910 ms | 57.258 ms | 44.975 ms | 70.772 ms | 51.930 ms | 40.521 ms | 33.714 ms | 9.144 ms | 52.055 ms | 45.585 ms | 2.077 ms |
| cross-correlation vec.vec | Float64 256^3 | 768.419 ms | 609.905 ms | 424.586 ms | 376.028 ms | 620.211 ms | 436.611 ms | 290.447 ms | 265.683 ms | — | 217.471 ms | 135.191 ms | 16.292 ms |
| cross-correlation vec.vec | Float64 512^3 | — | — | — | — | 4.786 s | 3.318 s | 2.160 s | 1.858 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 6.074 ms | 6.567 ms | 6.174 ms | 6.112 ms | 4.742 ms | 3.800 ms | 3.548 ms | 3.415 ms | 1.557 ms | 20.881 ms | 24.603 ms | 309.303 μs |
| inner spectral | Float32 128^3 | 1.678 ms | 1.641 ms | 1.709 ms | 1.616 ms | 573.506 μs | 529.326 μs | 527.676 μs | 529.245 μs | 669.926 μs | 2.049 ms | 581.033 μs | 254.113 μs |
| inner spectral | Float32 256^3 | 17.465 ms | 17.199 ms | 18.705 ms | 18.166 ms | 7.849 ms | 8.161 ms | 8.011 ms | 7.666 ms | — | 3.999 ms | 1.082 ms | 739.028 μs |
| inner spectral | Float32 512^3 | — | — | — | — | 78.468 ms | 79.565 ms | 79.283 ms | 78.713 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 150.309 μs | 152.802 μs | 150.041 μs | 153.956 μs | 88.700 μs | 97.261 μs | 88.091 μs | 87.361 μs | 275.972 μs | 1.780 ms | 526.140 μs | 193.153 μs |
| inner spectral | Float64 128^3 | 3.257 ms | 3.187 ms | 3.197 ms | 3.189 ms | 601.866 μs | 619.016 μs | 628.597 μs | 630.346 μs | 811.337 μs | 2.410 ms | 766.894 μs | 328.904 μs |
| inner spectral | Float64 256^3 | 27.816 ms | 28.026 ms | 28.065 ms | 28.147 ms | 15.916 ms | 16.087 ms | 16.069 ms | 15.835 ms | — | 7.953 ms | 2.174 ms | 1.219 ms |
| inner spectral | Float64 512^3 | — | — | — | — | 129.106 ms | 128.999 ms | 131.471 ms | 128.553 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 122.532 μs | 121.474 μs | 122.266 μs | 128.574 μs | 68.660 μs | 67.941 μs | 67.421 μs | 68.211 μs | 293.003 μs | 1.765 ms | 518.559 μs | 207.912 μs |
| inner vec.vec | Float32 128^3 | 1.278 ms | 1.275 ms | 1.346 ms | 1.286 ms | 310.603 μs | 311.603 μs | 309.114 μs | 310.483 μs | 308.353 μs | 1.623 ms | 264.045 μs | 113.121 μs |
| inner vec.vec | Float32 256^3 | 13.684 ms | 13.563 ms | 13.391 ms | 13.360 ms | 5.982 ms | 5.956 ms | 6.056 ms | 5.893 ms | — | 3.382 ms | 650.639 μs | 566.146 μs |
| inner vec.vec | Float32 512^3 | — | — | — | — | 57.471 ms | 56.849 ms | 56.755 ms | 56.696 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 66.271 μs | 66.667 μs | 66.309 μs | 67.193 μs | 38.420 μs | 38.340 μs | 38.301 μs | 38.460 μs | 98.731 μs | 1.278 ms | 250.252 μs | 78.381 μs |
| inner vec.vec | Float64 128^3 | 2.255 ms | 2.286 ms | 2.292 ms | 2.273 ms | 215.102 μs | 212.982 μs | 230.532 μs | 229.602 μs | 552.615 μs | 1.860 ms | 264.629 μs | 227.613 μs |
| inner vec.vec | Float64 256^3 | 23.368 ms | 23.570 ms | 22.645 ms | 23.069 ms | 13.001 ms | 12.999 ms | 13.012 ms | 13.030 ms | — | 5.634 ms | 1.408 ms | 1.074 ms |
| inner vec.vec | Float64 512^3 | — | — | — | — | 111.905 ms | 110.511 ms | 110.374 ms | 110.391 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 27.538 μs | 29.558 μs | 32.952 μs | 35.172 μs | 10.300 μs | 10.490 μs | 10.520 μs | 10.370 μs | 162.792 μs | 1.434 ms | 250.809 μs | 110.331 μs |
| integral scalar | Float32 128^3 | 113.400 μs | 108.417 μs | 110.182 μs | 113.181 μs | 59.491 μs | 59.571 μs | 60.341 μs | 60.610 μs | 228.932 μs | 1.318 ms | 498.427 μs | 103.911 μs |
| integral scalar | Float32 256^3 | 2.178 ms | 2.178 ms | 2.148 ms | 2.198 ms | 559.905 μs | 573.756 μs | 543.166 μs | 540.015 μs | — | 9.002 ms | 1.689 ms | 251.973 μs |
| integral scalar | Float32 512^3 | — | — | — | — | 10.690 ms | 11.047 ms | 10.218 ms | 10.492 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 10.911 μs | 10.766 μs | 10.747 μs | 11.064 μs | 6.794 μs | 6.486 μs | 6.848 μs | 6.684 μs | 95.301 μs | 1.534 ms | 335.134 μs | 81.891 μs |
| integral scalar | Float64 128^3 | 243.528 μs | 256.377 μs | 243.628 μs | 237.094 μs | 120.512 μs | 120.671 μs | 118.091 μs | 118.891 μs | 221.812 μs | 2.553 ms | 408.667 μs | 104.511 μs |
| integral scalar | Float64 256^3 | 5.271 ms | 4.816 ms | 5.071 ms | 5.087 ms | 2.017 ms | 1.944 ms | 1.950 ms | 1.990 ms | — | 10.817 ms | 2.011 ms | 260.473 μs |
| integral scalar | Float64 512^3 | — | — | — | — | 19.719 ms | 18.984 ms | 19.761 ms | 19.951 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.364 μs | 27.281 μs | 26.233 μs | 28.818 μs | 14.740 μs | 15.220 μs | 15.380 μs | 15.780 μs | 95.391 μs | 1.583 ms | 342.341 μs | 79.731 μs |
| integral spectral vec | Float32 128^3 | 67.985 ns | 68.105 ns | 68.078 ns | 68.363 ns | 70.297 ns | 73.526 ns | 69.817 ns | 69.026 ns | — | — | 317.457 μs | 55.981 μs |
| integral spectral vec | Float32 256^3 | 67.784 ns | 69.094 ns | 68.335 ns | 69.317 ns | 70.575 ns | 74.079 ns | 70.278 ns | 69.246 ns | — | — | 299.775 μs | 50.261 μs |
| integral spectral vec | Float32 512^3 | — | — | — | — | 71.168 ns | 76.688 ns | 72.982 ns | 68.942 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 67.887 ns | 67.971 ns | 68.011 ns | 67.882 ns | 70.565 ns | 76.156 ns | 69.550 ns | 71.214 ns | — | — | 316.532 μs | 53.991 μs |
| integral spectral vec | Float64 128^3 | 70.912 ns | 69.573 ns | 69.502 ns | 69.698 ns | 74.697 ns | 73.892 ns | 75.325 ns | 74.779 ns | — | — | 313.854 μs | 49.151 μs |
| integral spectral vec | Float64 256^3 | 74.535 ns | 69.957 ns | 71.417 ns | 70.402 ns | 76.562 ns | 74.703 ns | 77.031 ns | 76.507 ns | — | — | 162.397 μs | 52.850 μs |
| integral spectral vec | Float64 512^3 | — | — | — | — | 76.606 ns | 78.892 ns | 80.771 ns | 80.423 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 69.870 ns | 69.400 ns | 69.279 ns | 68.970 ns | 76.291 ns | 76.911 ns | 75.273 ns | 77.413 ns | — | — | 303.750 μs | 59.781 μs |
| l2norm vec | Float32 128^3 | 496.324 μs | 523.511 μs | 511.792 μs | 501.651 μs | 166.301 μs | 166.672 μs | 166.042 μs | 167.031 μs | 196.632 μs | 1.582 ms | 262.024 μs | 96.431 μs |
| l2norm vec | Float32 256^3 | 7.000 ms | 7.170 ms | 6.756 ms | 6.885 ms | 2.802 ms | 2.635 ms | 2.448 ms | 2.410 ms | — | 3.219 ms | 567.486 μs | 344.154 μs |
| l2norm vec | Float32 512^3 | — | — | — | — | 26.369 ms | 28.098 ms | 28.146 ms | 26.477 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 40.460 μs | 42.598 μs | 42.232 μs | 41.715 μs | 21.941 μs | 22.590 μs | 22.060 μs | 19.080 μs | 85.641 μs | 1.361 ms | 247.590 μs | 83.641 μs |
| l2norm vec | Float64 128^3 | 767.805 μs | 759.195 μs | 765.750 μs | 791.552 μs | 63.121 μs | 63.020 μs | 63.381 μs | 62.941 μs | 344.333 μs | 1.876 ms | 382.666 μs | 151.392 μs |
| l2norm vec | Float64 256^3 | 11.220 ms | 11.435 ms | 11.451 ms | 11.758 ms | 5.572 ms | 5.488 ms | 5.557 ms | 5.470 ms | — | 5.670 ms | 1.275 ms | 592.297 μs |
| l2norm vec | Float64 512^3 | — | — | — | — | 54.771 ms | 54.727 ms | 54.749 ms | 54.726 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 16.464 μs | 16.203 μs | 16.743 μs | 16.332 μs | 4.073 μs | 4.037 μs | 3.853 μs | 4.166 μs | 134.871 μs | 1.402 ms | 101.913 μs | 116.891 μs |
| lpnorm vec Inf | Float32 128^3 | 1.406 ms | 5.670 ms | 3.066 ms | 1.897 ms | 460.005 μs | 375.843 μs | 336.824 μs | 313.462 μs | 592.145 μs | 3.080 ms | 671.607 μs | 141.592 μs |
| lpnorm vec Inf | Float32 256^3 | 23.026 ms | 49.984 ms | 27.046 ms | 15.439 ms | 18.521 ms | 10.809 ms | 8.185 ms | 8.526 ms | — | 13.216 ms | 2.615 ms | 582.917 μs |
| lpnorm vec Inf | Float32 512^3 | — | — | — | — | 133.478 ms | 86.939 ms | 75.743 ms | 73.265 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 101.323 μs | 671.481 μs | 364.136 μs | 217.019 μs | 61.141 μs | 49.330 μs | 41.811 μs | 42.150 μs | 155.751 μs | 1.641 ms | 384.937 μs | 114.502 μs |
| lpnorm vec Inf | Float64 128^3 | 3.314 ms | 6.433 ms | 3.909 ms | 3.233 ms | 1.134 ms | 1.111 ms | 998.952 μs | 917.658 μs | 660.476 μs | 3.883 ms | 892.140 μs | 235.313 μs |
| lpnorm vec Inf | Float64 256^3 | 46.830 ms | 61.856 ms | 34.920 ms | 23.496 ms | 32.658 ms | 21.320 ms | 15.537 ms | 17.128 ms | — | 14.730 ms | 4.731 ms | 957.511 μs |
| lpnorm vec Inf | Float64 512^3 | — | — | — | — | 247.062 ms | 161.625 ms | 140.362 ms | 138.177 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 247.350 μs | 769.630 μs | 451.701 μs | 281.444 μs | 111.411 μs | 93.091 μs | 76.691 μs | 72.640 μs | 166.092 μs | 1.711 ms | 414.213 μs | 112.441 μs |
| maximum scalar | Float32 128^3 | 343.179 μs | 342.185 μs | 341.855 μs | 343.284 μs | 233.623 μs | 232.952 μs | 230.723 μs | 231.102 μs | 223.322 μs | 2.331 ms | 499.085 μs | 95.251 μs |
| maximum scalar | Float32 256^3 | 2.908 ms | 2.940 ms | 2.925 ms | 2.891 ms | 1.848 ms | 1.890 ms | 1.897 ms | 1.843 ms | — | 9.121 ms | 1.595 ms | 249.532 μs |
| maximum scalar | Float32 512^3 | — | — | — | — | 23.848 ms | 23.635 ms | 28.431 ms | 26.625 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 42.654 μs | 42.641 μs | 42.642 μs | 42.640 μs | 28.880 μs | 28.890 μs | 28.860 μs | 28.930 μs | 101.731 μs | 1.564 ms | 356.605 μs | 87.732 μs |
| maximum scalar | Float64 128^3 | 557.677 μs | 565.583 μs | 560.615 μs | 550.517 μs | 435.094 μs | 435.835 μs | 438.945 μs | 441.424 μs | 244.072 μs | 2.772 ms | 590.993 μs | 104.391 μs |
| maximum scalar | Float64 256^3 | 6.803 ms | 6.341 ms | 6.531 ms | 6.571 ms | 4.123 ms | 4.113 ms | 4.841 ms | 3.964 ms | — | 12.659 ms | 2.596 ms | 293.543 μs |
| maximum scalar | Float64 512^3 | — | — | — | — | 45.073 ms | 43.204 ms | 44.383 ms | 43.078 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 65.465 μs | 65.207 μs | 65.402 μs | 66.478 μs | 54.721 μs | 54.891 μs | 54.831 μs | 54.821 μs | 99.451 μs | 1.634 ms | 362.143 μs | 102.931 μs |
| maximum(norm) vec | Float32 128^3 | 1.857 ms | 1.850 ms | 1.856 ms | 1.856 ms | 774.138 μs | 775.448 μs | 772.618 μs | 772.578 μs | — | — | 528.932 μs | 116.401 μs |
| maximum(norm) vec | Float32 256^3 | 15.394 ms | 15.401 ms | 15.309 ms | 15.369 ms | 8.498 ms | 8.109 ms | 8.022 ms | 8.333 ms | — | — | 2.136 ms | 358.784 μs |
| maximum(norm) vec | Float32 512^3 | — | — | — | — | 63.883 ms | 64.994 ms | 65.666 ms | 60.116 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 225.513 μs | 225.213 μs | 225.051 μs | 224.996 μs | 96.461 μs | 97.171 μs | 96.501 μs | 96.671 μs | — | — | 350.398 μs | 93.671 μs |
| maximum(norm) vec | Float64 128^3 | 5.352 ms | 5.353 ms | 5.343 ms | 5.337 ms | 1.585 ms | 1.586 ms | 1.586 ms | 1.583 ms | — | — | 799.036 μs | 228.253 μs |
| maximum(norm) vec | Float64 256^3 | 43.808 ms | 43.733 ms | 43.304 ms | 43.411 ms | 15.693 ms | 14.204 ms | 14.062 ms | 13.814 ms | — | — | 4.228 ms | 1.049 ms |
| maximum(norm) vec | Float64 512^3 | — | — | — | — | 121.105 ms | 116.761 ms | 120.970 ms | 115.756 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 651.504 μs | 652.016 μs | 651.976 μs | 651.660 μs | 197.172 μs | 197.152 μs | 197.392 μs | 197.792 μs | — | — | 383.337 μs | 110.241 μs |
| mean spectral vec | Float32 128^3 | 70.324 ns | 70.922 ns | 70.948 ns | 71.788 ns | 73.560 ns | 71.898 ns | 74.205 ns | 73.136 ns | — | — | 308.514 μs | 55.850 μs |
| mean spectral vec | Float32 256^3 | 70.641 ns | 71.118 ns | 71.496 ns | 71.424 ns | 74.052 ns | 72.288 ns | 74.831 ns | 74.040 ns | — | — | 170.904 μs | 48.701 μs |
| mean spectral vec | Float32 512^3 | — | — | — | — | 74.822 ns | 74.616 ns | 77.133 ns | 76.656 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 70.581 ns | 70.389 ns | 70.261 ns | 71.427 ns | 74.518 ns | 74.779 ns | 73.763 ns | 76.087 ns | — | — | 315.433 μs | 47.661 μs |
| mean spectral vec | Float64 128^3 | 74.241 ns | 73.428 ns | 73.146 ns | 73.693 ns | 77.305 ns | 80.135 ns | 78.178 ns | 78.245 ns | — | — | 295.537 μs | 50.101 μs |
| mean spectral vec | Float64 256^3 | 74.676 ns | 74.353 ns | 78.820 ns | 73.872 ns | 78.296 ns | 80.934 ns | 79.207 ns | 79.102 ns | — | — | 295.185 μs | 52.330 μs |
| mean spectral vec | Float64 512^3 | — | — | — | — | 79.310 ns | 84.487 ns | 82.957 ns | 83.261 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 72.442 ns | 72.592 ns | 72.310 ns | 72.552 ns | 78.844 ns | 82.656 ns | 78.312 ns | 81.397 ns | — | — | 242.478 μs | 61.530 μs |
| mean vector | Float32 128^3 | 533.311 μs | 537.045 μs | 531.223 μs | 523.171 μs | 197.522 μs | 183.591 μs | 196.522 μs | 199.162 μs | 633.756 μs | 4.808 ms | 940.896 μs | 220.302 μs |
| mean vector | Float32 256^3 | 7.519 ms | 7.467 ms | 7.203 ms | 7.407 ms | 3.442 ms | 3.295 ms | 3.318 ms | 3.120 ms | — | 16.657 ms | 5.236 ms | 1.256 ms |
| mean vector | Float32 512^3 | — | — | — | — | 32.767 ms | 34.338 ms | 34.414 ms | 34.655 ms | — | — | — | — |
| mean vector | Float32 64^3 | 42.235 μs | 41.908 μs | 42.298 μs | 45.238 μs | 25.151 μs | 25.560 μs | 26.340 μs | 24.580 μs | 162.362 μs | 1.846 ms | 403.682 μs | 95.132 μs |
| mean vector | Float64 128^3 | 1.585 ms | 1.570 ms | 1.650 ms | 1.602 ms | 399.504 μs | 398.394 μs | 398.024 μs | 381.823 μs | 657.486 μs | 5.195 ms | 1.043 ms | 250.023 μs |
| mean vector | Float64 256^3 | 15.115 ms | 14.689 ms | 15.052 ms | 15.146 ms | 8.345 ms | 8.951 ms | 7.861 ms | 7.927 ms | — | 17.799 ms | 6.222 ms | 1.431 ms |
| mean vector | Float64 512^3 | — | — | — | — | 59.505 ms | 54.611 ms | 62.191 ms | 54.804 ms | — | — | — | — |
| mean vector | Float64 64^3 | 82.340 μs | 82.596 μs | 82.762 μs | 82.817 μs | 46.430 μs | 45.880 μs | 45.731 μs | 46.001 μs | 156.311 μs | 1.913 ms | 397.329 μs | 104.491 μs |
| mean(det) tensor | Float32 128^3 | 2.470 ms | 2.452 ms | 2.492 ms | 2.479 ms | 775.598 μs | 746.647 μs | 780.828 μs | 760.517 μs | — | — | 606.174 μs | 216.973 μs |
| mean(det) tensor | Float32 256^3 | 24.879 ms | 24.599 ms | 24.749 ms | 25.095 ms | 16.008 ms | 16.121 ms | 15.834 ms | 16.114 ms | — | — | 2.755 ms | 827.249 μs |
| mean(det) tensor | Float32 512^3 | — | — | — | — | 116.056 ms | 103.252 ms | 106.714 ms | 107.227 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 101.867 μs | 101.918 μs | 101.133 μs | 102.115 μs | 67.380 μs | 67.301 μs | 68.231 μs | 68.360 μs | — | — | 369.239 μs | 96.492 μs |
| mean(det) tensor | Float64 128^3 | 5.413 ms | 5.411 ms | 5.319 ms | 5.416 ms | 2.528 ms | 2.574 ms | 2.515 ms | 2.403 ms | — | — | 780.511 μs | 278.443 μs |
| mean(det) tensor | Float64 256^3 | 48.133 ms | 49.618 ms | 49.772 ms | 48.437 ms | 30.276 ms | 30.852 ms | 30.873 ms | 29.208 ms | — | — | 4.115 ms | 1.529 ms |
| mean(det) tensor | Float64 512^3 | — | — | — | — | 202.383 ms | 199.329 ms | 225.172 ms | 221.797 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 229.834 μs | 226.271 μs | 229.621 μs | 229.020 μs | 129.971 μs | 131.021 μs | 131.931 μs | 129.592 μs | — | — | 385.327 μs | 110.861 μs |
| mean(norm) vec | Float32 128^3 | 1.598 ms | 1.601 ms | 1.596 ms | 1.594 ms | 607.756 μs | 608.697 μs | 606.247 μs | 597.655 μs | — | — | 532.216 μs | 118.782 μs |
| mean(norm) vec | Float32 256^3 | 13.189 ms | 13.166 ms | 13.200 ms | 13.130 ms | 7.570 ms | 7.169 ms | 7.120 ms | 7.426 ms | — | — | 2.087 ms | 372.454 μs |
| mean(norm) vec | Float32 512^3 | — | — | — | — | 58.272 ms | 58.321 ms | 58.692 ms | 53.962 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 193.056 μs | 192.968 μs | 192.997 μs | 192.960 μs | 75.931 μs | 75.880 μs | 75.801 μs | 75.881 μs | — | — | 357.547 μs | 82.152 μs |
| mean(norm) vec | Float64 128^3 | 5.284 ms | 5.284 ms | 5.275 ms | 5.175 ms | 1.444 ms | 1.443 ms | 1.443 ms | 1.429 ms | — | — | 719.008 μs | 214.393 μs |
| mean(norm) vec | Float64 256^3 | 43.072 ms | 43.303 ms | 42.917 ms | 42.675 ms | 14.160 ms | 13.279 ms | 13.540 ms | 13.275 ms | — | — | 3.609 ms | 937.881 μs |
| mean(norm) vec | Float64 512^3 | — | — | — | — | 108.676 ms | 105.941 ms | 112.332 ms | 104.864 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 644.449 μs | 645.469 μs | 644.414 μs | 632.472 μs | 179.902 μs | 180.292 μs | 179.252 μs | 182.882 μs | — | — | 378.522 μs | 97.391 μs |
| mean(tr) tensor | Float32 128^3 | 395.648 μs | 400.391 μs | 417.426 μs | 394.809 μs | 208.492 μs | 200.982 μs | 195.122 μs | 186.782 μs | — | — | 494.486 μs | 118.752 μs |
| mean(tr) tensor | Float32 256^3 | 6.788 ms | 6.819 ms | 6.766 ms | 6.775 ms | 3.285 ms | 3.268 ms | 3.202 ms | 3.266 ms | — | — | 1.921 ms | 347.843 μs |
| mean(tr) tensor | Float32 512^3 | — | — | — | — | 37.432 ms | 32.751 ms | 33.346 ms | 33.338 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 35.425 μs | 34.565 μs | 34.820 μs | 34.552 μs | 25.640 μs | 24.480 μs | 25.470 μs | 24.870 μs | — | — | 358.443 μs | 86.181 μs |
| mean(tr) tensor | Float64 128^3 | 1.330 ms | 1.320 ms | 1.339 ms | 1.327 ms | 401.624 μs | 405.934 μs | 357.554 μs | 354.103 μs | — | — | 582.415 μs | 158.182 μs |
| mean(tr) tensor | Float64 256^3 | 13.692 ms | 13.983 ms | 13.790 ms | 13.851 ms | 7.067 ms | 7.204 ms | 7.086 ms | 6.751 ms | — | — | 2.349 ms | 586.687 μs |
| mean(tr) tensor | Float64 512^3 | — | — | — | — | 65.776 ms | 65.974 ms | 75.282 ms | 76.141 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 70.185 μs | 68.289 μs | 67.845 μs | 67.982 μs | 43.210 μs | 43.141 μs | 42.650 μs | 43.141 μs | — | — | 310.224 μs | 98.281 μs |
| radial_correlation vec | Float32 128^3 | 41.163 ms | 40.545 ms | 36.544 ms | 38.080 ms | 35.831 ms | 26.677 ms | 23.279 ms | 22.107 ms | 5.783 ms | 42.875 ms | 1.617 ms | 764.119 μs |
| radial_correlation vec | Float32 256^3 | 623.422 ms | 481.016 ms | 348.134 ms | 293.562 ms | 785.305 ms | 541.151 ms | 324.192 ms | 260.480 ms | — | 185.439 ms | 9.481 ms | 5.598 ms |
| radial_correlation vec | Float32 512^3 | — | — | — | — | 7.887 s | 5.300 s | 2.924 s | 2.168 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.612 ms | 6.396 ms | 6.164 ms | 6.363 ms | 3.657 ms | 3.498 ms | 3.666 ms | 3.585 ms | 1.010 ms | 19.917 ms | 677.607 μs | 265.364 μs |
| radial_correlation vec | Float64 128^3 | 83.653 ms | 71.915 ms | 56.215 ms | 41.289 ms | 68.417 ms | 52.441 ms | 37.958 ms | 32.627 ms | 9.025 ms | 52.060 ms | 45.597 ms | 2.011 ms |
| radial_correlation vec | Float64 256^3 | 753.759 ms | 602.903 ms | 417.684 ms | 378.734 ms | 584.739 ms | 418.431 ms | 282.432 ms | 251.434 ms | — | 219.151 ms | 136.364 ms | 14.793 ms |
| radial_correlation vec | Float64 512^3 | — | — | — | — | 4.622 s | 3.179 s | 2.060 s | 1.779 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.844 ms | 6.195 ms | 5.976 ms | 5.827 ms | 4.341 ms | 3.649 ms | 3.473 ms | 3.419 ms | 1.413 ms | 21.203 ms | 23.962 ms | 332.923 μs |
| radial_spectrum vec | Float32 128^3 | 7.677 ms | 6.451 ms | 8.022 ms | 8.200 ms | 6.323 ms | 4.770 ms | 5.777 ms | 6.003 ms | 1.415 ms | 27.166 ms | 821.492 μs | 301.463 μs |
| radial_spectrum vec | Float32 256^3 | 61.645 ms | 48.585 ms | 48.479 ms | 42.703 ms | 50.072 ms | 33.099 ms | 31.191 ms | 29.876 ms | — | 96.772 ms | 2.468 ms | 929.290 μs |
| radial_spectrum vec | Float32 512^3 | — | — | — | — | 399.113 ms | 236.199 ms | 179.391 ms | 153.977 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 997.899 μs | 1.352 ms | 1.569 ms | 1.622 ms | 821.999 μs | 917.169 μs | 1.165 ms | 1.314 ms | 344.443 μs | 16.995 ms | 559.122 μs | 168.323 μs |
| radial_spectrum vec | Float64 128^3 | 7.692 ms | 6.821 ms | 6.225 ms | 5.635 ms | 6.538 ms | 4.623 ms | 4.379 ms | 4.424 ms | 1.515 ms | 29.791 ms | 27.835 ms | 369.315 μs |
| radial_spectrum vec | Float64 256^3 | 62.834 ms | 46.484 ms | 35.375 ms | 30.287 ms | 51.923 ms | 32.034 ms | 25.355 ms | 22.623 ms | — | 110.504 ms | 65.951 ms | 1.375 ms |
| radial_spectrum vec | Float64 512^3 | — | — | — | — | 414.615 ms | 252.253 ms | 164.160 ms | 123.648 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 1.001 ms | 753.724 μs | 1.048 ms | 1.108 ms | 846.368 μs | 683.987 μs | 828.479 μs | 956.318 μs | 380.613 μs | 16.740 ms | 14.885 ms | 180.582 μs |
| weighted_inner vec | Float32 128^3 | 12.769 ms | 12.743 ms | 12.759 ms | 12.619 ms | 10.293 ms | 10.312 ms | 10.352 ms | 10.292 ms | — | — | 781.489 μs | 155.612 μs |
| weighted_inner vec | Float32 256^3 | 101.316 ms | 101.074 ms | 100.560 ms | 100.045 ms | 81.352 ms | 80.999 ms | 82.824 ms | 80.931 ms | — | — | 3.664 ms | 629.417 μs |
| weighted_inner vec | Float32 512^3 | — | — | — | — | 641.427 ms | 645.749 ms | 645.721 ms | 645.320 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.629 ms | 1.627 ms | 1.633 ms | 1.608 ms | 1.285 ms | 1.282 ms | 1.285 ms | 1.340 ms | — | — | 435.151 μs | 93.402 μs |
| weighted_inner vec | Float64 128^3 | 13.922 ms | 13.913 ms | 13.689 ms | 13.752 ms | 10.894 ms | 10.902 ms | 10.901 ms | 10.895 ms | — | — | 895.200 μs | 173.772 μs |
| weighted_inner vec | Float64 256^3 | 112.122 ms | 112.189 ms | 110.242 ms | 112.406 ms | 85.807 ms | 85.849 ms | 85.834 ms | 85.861 ms | — | — | 4.606 ms | 1.063 ms |
| weighted_inner vec | Float64 512^3 | — | — | — | — | 679.598 ms | 682.375 ms | 680.618 ms | 680.184 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.724 ms | 1.725 ms | 1.713 ms | 1.727 ms | 1.357 ms | 1.442 ms | 1.411 ms | 1.354 ms | — | — | 427.115 μs | 118.101 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.891 ms | 12.754 ms | 12.818 ms | 12.588 ms | 10.304 ms | 10.368 ms | 10.365 ms | 10.299 ms | — | — | 785.379 μs | 168.642 μs |
| weighted_inner vec.vec | Float32 256^3 | 101.369 ms | 100.652 ms | 101.275 ms | 100.337 ms | 81.031 ms | 81.600 ms | 83.731 ms | 81.502 ms | — | — | 3.636 ms | 833.779 μs |
| weighted_inner vec.vec | Float32 512^3 | — | — | — | — | 643.935 ms | 647.162 ms | 643.982 ms | 642.973 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.647 ms | 1.629 ms | 1.638 ms | 1.597 ms | 1.302 ms | 1.284 ms | 1.307 ms | 1.343 ms | — | — | 393.354 μs | 98.001 μs |
| weighted_inner vec.vec | Float64 128^3 | 14.416 ms | 14.195 ms | 14.171 ms | 13.930 ms | 10.921 ms | 10.941 ms | 10.948 ms | 10.931 ms | — | — | 887.918 μs | 269.913 μs |
| weighted_inner vec.vec | Float64 256^3 | 114.884 ms | 114.588 ms | 114.138 ms | 113.243 ms | 85.985 ms | 86.085 ms | 86.256 ms | 86.074 ms | — | — | 4.631 ms | 1.542 ms |
| weighted_inner vec.vec | Float64 512^3 | — | — | — | — | 682.569 ms | 683.018 ms | 778.541 ms | 774.587 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.772 ms | 1.731 ms | 1.723 ms | 1.733 ms | 1.374 ms | 1.458 ms | 1.422 ms | 1.361 ms | — | — | 443.334 μs | 123.831 μs |

