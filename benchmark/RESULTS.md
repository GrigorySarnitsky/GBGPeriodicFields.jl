# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-07-22 at commit `5934a78c` on Julia 1.12.6, assembled on host `Aiporetne` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–256³) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The pre-swap archive columns (GTX 1070, RX 6700 XT) keep their pre-rewrite measurements — retired hardware is not re-swept; every live column (both CPUs, RX 7900 XTX, RTX 5070 Ti) is measured at the decision-38/39 rewrite. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh` plus the per-card / per-CPU archive in `benchmark/results/` (PERFORMANCE.md §6). ~10% jitter.

## fft

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 4.980 ms | 3.224 ms | 2.380 ms | 2.127 ms | 4.694 ms | 2.358 ms | 1.276 ms | 766.597 μs | 788.067 μs | 2.421 ms | 1.261 ms | 119.432 μs |
| to_physical scalar | Float32 256^3 | 116.555 ms | 70.842 ms | 40.836 ms | 41.060 ms | 185.631 ms | 100.977 ms | 56.725 ms | 35.913 ms | — | 7.945 ms | 2.307 ms | 1.082 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | 2.102 s | 1.121 s | 629.538 ms | 391.987 ms | — | — | 13.398 ms | — |
| to_physical scalar | Float32 64^3 | 392.728 μs | 246.460 μs | 166.355 μs | 156.554 μs | 313.733 μs | 176.991 μs | 102.071 μs | 70.731 μs | 124.402 μs | 1.497 ms | 1.071 ms | 116.271 μs |
| to_physical scalar | Float64 128^3 | 8.558 ms | 5.753 ms | 4.700 ms | 4.588 ms | 10.098 ms | 5.437 ms | 3.023 ms | 1.814 ms | 1.905 ms | 3.750 ms | 1.646 ms | 493.576 μs |
| to_physical scalar | Float64 256^3 | 149.358 ms | 100.860 ms | 80.808 ms | 75.682 ms | 113.758 ms | 72.813 ms | 52.678 ms | 38.243 ms | — | 14.463 ms | 5.748 ms | 3.828 ms |
| to_physical scalar | Float64 512^3 | — | — | — | — | 938.673 ms | 616.490 ms | 455.138 ms | 412.947 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 696.185 μs | 409.495 μs | 301.721 μs | 256.983 μs | 520.215 μs | 293.813 μs | 165.502 μs | 113.061 μs | 331.873 μs | 1.784 ms | 992.328 μs | 126.861 μs |
| to_physical vector | Float32 128^3 | 14.867 ms | 11.525 ms | 7.713 ms | 7.514 ms | 14.441 ms | 10.194 ms | 5.241 ms | 3.770 ms | 2.507 ms | 4.595 ms | 1.724 ms | 303.484 μs |
| to_physical vector | Float32 256^3 | 362.171 ms | 261.194 ms | 171.345 ms | 139.481 ms | 593.375 ms | 412.807 ms | 220.879 ms | 161.935 ms | — | 14.844 ms | 5.773 ms | 3.475 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | 6.264 s | 4.295 s | 2.292 s | 1.655 s | — | — | 51.336 ms | — |
| to_physical vector | Float32 64^3 | 1.301 ms | 963.761 μs | 571.395 μs | 513.631 μs | 986.800 μs | 691.107 μs | 313.064 μs | 218.832 μs | 380.054 μs | 1.776 ms | 1.186 ms | 124.671 μs |
| to_physical vector | Float64 128^3 | 37.059 ms | 30.932 ms | 23.908 ms | 20.683 ms | 41.775 ms | 29.248 ms | 13.952 ms | 11.001 ms | 5.630 ms | 8.090 ms | 2.788 ms | 1.455 ms |
| to_physical vector | Float64 256^3 | 443.144 ms | 340.756 ms | 245.927 ms | 228.392 ms | 358.604 ms | 268.701 ms | 174.734 ms | 156.094 ms | — | 22.812 ms | 13.720 ms | 11.335 ms |
| to_physical vector | Float64 512^3 | — | — | — | — | 2.810 s | 2.123 s | 1.404 s | 1.254 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.525 ms | 2.100 ms | 1.494 ms | 1.244 ms | 1.627 ms | 1.123 ms | 559.505 μs | 425.434 μs | 811.437 μs | 2.301 ms | 1.271 ms | 203.172 μs |
| to_spectral scalar | Float32 128^3 | 4.393 ms | 2.840 ms | 1.758 ms | 1.234 ms | 4.577 ms | 2.267 ms | 1.228 ms | 701.236 μs | 488.254 μs | 2.072 ms | 1.113 ms | 94.781 μs |
| to_spectral scalar | Float32 256^3 | 116.722 ms | 69.377 ms | 35.916 ms | 36.111 ms | 187.531 ms | 101.587 ms | 55.296 ms | 33.987 ms | — | 5.009 ms | 1.905 ms | 729.758 μs |
| to_spectral scalar | Float32 512^3 | — | — | — | — | 2.085 s | 1.101 s | 604.970 ms | 363.802 ms | — | — | 9.591 ms | — |
| to_spectral scalar | Float32 64^3 | 369.447 μs | 207.222 μs | 128.605 μs | 109.080 μs | 308.093 μs | 167.252 μs | 90.861 μs | 58.901 μs | 89.181 μs | 1.538 ms | 1.110 ms | 81.641 μs |
| to_spectral scalar | Float64 128^3 | 7.598 ms | 4.863 ms | 4.022 ms | 3.401 ms | 10.407 ms | 5.423 ms | 2.870 ms | 1.662 ms | 1.501 ms | 3.125 ms | 1.651 ms | 429.816 μs |
| to_spectral scalar | Float64 256^3 | 165.401 ms | 106.495 ms | 75.529 ms | 65.147 ms | 209.455 ms | 115.748 ms | 57.997 ms | 45.507 ms | — | 12.871 ms | 5.179 ms | 3.122 ms |
| to_spectral scalar | Float64 512^3 | — | — | — | — | 1.721 s | 965.405 ms | 592.631 ms | 434.514 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 637.181 μs | 358.886 μs | 234.579 μs | 195.157 μs | 501.455 μs | 273.013 μs | 152.042 μs | 95.151 μs | 265.683 μs | 1.745 ms | 1.077 ms | 110.151 μs |
| to_spectral vector | Float32 128^3 | 13.606 ms | 10.031 ms | 6.613 ms | 5.855 ms | 14.952 ms | 10.575 ms | 5.189 ms | 3.379 ms | 1.355 ms | 3.183 ms | 1.354 ms | 192.732 μs |
| to_spectral vector | Float32 256^3 | 353.093 ms | 252.211 ms | 152.232 ms | 122.202 ms | 581.526 ms | 400.321 ms | 211.229 ms | 151.674 ms | — | 11.819 ms | 3.512 ms | 2.220 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | 6.235 s | 4.261 s | 2.212 s | 1.570 s | — | — | 20.305 ms | — |
| to_spectral vector | Float32 64^3 | 1.205 ms | 865.560 μs | 423.904 μs | 460.359 μs | 975.010 μs | 649.137 μs | 286.614 μs | 180.601 μs | 230.522 μs | 1.566 ms | 924.065 μs | 96.331 μs |
| to_spectral vector | Float64 128^3 | 34.770 ms | 23.543 ms | 24.757 ms | 17.240 ms | 41.892 ms | 30.029 ms | 13.163 ms | 9.962 ms | 4.144 ms | 6.538 ms | 2.420 ms | 1.170 ms |
| to_spectral vector | Float64 256^3 | 508.121 ms | 369.376 ms | 233.819 ms | 206.784 ms | 635.754 ms | 445.098 ms | 251.361 ms | 194.583 ms | — | 20.041 ms | 11.730 ms | 9.165 ms |
| to_spectral vector | Float64 512^3 | — | — | — | — | 5.055 s | 3.600 s | 2.031 s | 1.564 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.117 ms | 1.665 ms | 1.001 ms | 801.410 μs | 1.544 ms | 1.079 ms | 516.515 μs | 344.793 μs | 596.836 μs | 2.151 ms | 1.215 ms | 217.012 μs |

## algebra

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 416.332 μs | 251.552 μs | 174.849 μs | 74.428 μs | 161.712 μs | 84.051 μs | 44.570 μs | 34.700 μs | 351.303 μs | 1.943 ms | 1.146 ms | 79.791 μs |
| add! scalar | Float32 256^3 | 8.125 ms | 7.435 ms | 5.635 ms | 5.147 ms | 3.471 ms | 2.984 ms | 2.738 ms | 2.807 ms | — | 6.480 ms | 1.935 ms | 325.934 μs |
| add! scalar | Float32 512^3 | — | — | — | — | 40.521 ms | 36.516 ms | 36.715 ms | 37.318 ms | — | — | 7.478 ms | — |
| add! scalar | Float32 64^3 | 43.044 μs | 21.090 μs | 10.101 μs | 10.041 μs | 21.450 μs | 12.671 μs | 7.020 μs | 6.593 μs | 85.391 μs | 1.599 ms | 1.040 ms | 59.400 μs |
| add! scalar | Float64 128^3 | 1.482 ms | 1.300 ms | 949.150 μs | 807.501 μs | 326.784 μs | 165.042 μs | 87.041 μs | 72.791 μs | 354.693 μs | 2.024 ms | 1.185 ms | 98.381 μs |
| add! scalar | Float64 256^3 | 16.907 ms | 15.346 ms | 11.805 ms | 11.035 ms | 10.172 ms | 8.571 ms | 8.453 ms | 8.583 ms | — | 5.550 ms | 1.863 ms | 560.277 μs |
| add! scalar | Float64 512^3 | — | — | — | — | 83.759 ms | 73.022 ms | 73.425 ms | 74.315 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 85.456 μs | 47.117 μs | 21.409 μs | 17.346 μs | 40.360 μs | 24.450 μs | 11.950 μs | 9.240 μs | 83.741 μs | 1.494 ms | 1.042 ms | 55.520 μs |
| combine! vec | Float32 128^3 | 2.584 ms | 2.358 ms | 1.801 ms | 1.580 ms | 660.127 μs | 331.373 μs | 158.542 μs | 120.451 μs | — | — | 1.460 ms | 183.342 μs |
| combine! vec | Float32 256^3 | 25.389 ms | 23.252 ms | 18.238 ms | 16.871 ms | 13.691 ms | 13.935 ms | 13.585 ms | 13.971 ms | — | — | 4.150 ms | 1.018 ms |
| combine! vec | Float32 512^3 | — | — | — | — | 115.790 ms | 108.965 ms | 109.700 ms | 111.482 ms | — | — | 19.880 ms | — |
| combine! vec | Float32 64^3 | 129.169 μs | 69.637 μs | 38.306 μs | 18.942 μs | 65.570 μs | 39.021 μs | 20.381 μs | 14.700 μs | — | — | 1.124 ms | 63.670 μs |
| combine! vec | Float64 128^3 | 6.051 ms | 5.368 ms | 4.087 ms | 3.750 ms | 2.239 ms | 1.887 ms | 1.548 ms | 1.504 ms | — | — | 1.695 ms | 244.243 μs |
| combine! vec | Float64 256^3 | 51.126 ms | 46.768 ms | 36.895 ms | 34.211 ms | 28.627 ms | 26.813 ms | 26.989 ms | 27.245 ms | — | — | 4.922 ms | 1.583 ms |
| combine! vec | Float64 512^3 | — | — | — | — | 231.380 ms | 219.425 ms | 219.133 ms | 221.982 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 269.194 μs | 146.062 μs | 79.031 μs | 45.485 μs | 122.631 μs | 68.160 μs | 34.361 μs | 28.070 μs | — | — | 1.119 ms | 64.941 μs |
| cross! | Float32 128^3 | 2.874 ms | 2.410 ms | 2.094 ms | 1.968 ms | 1.923 ms | 977.220 μs | 491.115 μs | 263.612 μs | 1.223 ms | 3.445 ms | 1.087 ms | 133.602 μs |
| cross! | Float32 256^3 | 27.407 ms | 25.022 ms | 23.173 ms | 22.195 ms | 25.813 ms | 16.513 ms | 12.541 ms | 12.583 ms | — | 14.690 ms | 1.775 ms | 822.829 μs |
| cross! | Float32 512^3 | — | — | — | — | 188.003 ms | 121.172 ms | 110.450 ms | 111.119 ms | — | — | 7.558 ms | — |
| cross! | Float32 64^3 | 254.125 μs | 128.766 μs | 70.290 μs | 38.482 μs | 224.502 μs | 117.431 μs | 59.161 μs | 32.521 μs | 219.582 μs | 1.665 ms | 1.031 ms | 57.391 μs |
| cross! | Float64 128^3 | 6.471 ms | 5.657 ms | 5.083 ms | 4.881 ms | 3.826 ms | 2.306 ms | 1.547 ms | 1.473 ms | 1.263 ms | 2.603 ms | 1.367 ms | 246.643 μs |
| cross! | Float64 256^3 | 55.411 ms | 50.529 ms | 47.422 ms | 45.336 ms | 45.453 ms | 29.030 ms | 27.392 ms | 27.426 ms | — | 15.625 ms | 2.733 ms | 1.593 ms |
| cross! | Float64 512^3 | — | — | — | — | 298.099 ms | 228.886 ms | 220.800 ms | 222.293 ms | — | — | — | — |
| cross! | Float64 64^3 | 364.797 μs | 184.344 μs | 99.092 μs | 53.814 μs | 225.042 μs | 116.151 μs | 64.561 μs | 35.930 μs | 216.592 μs | 1.846 ms | 1.103 ms | 62.771 μs |
| det! tensor | Float32 128^3 | 3.251 ms | 2.405 ms | 1.968 ms | 1.787 ms | 2.239 ms | 1.101 ms | 548.306 μs | 299.183 μs | — | — | 1.218 ms | 184.122 μs |
| det! tensor | Float32 256^3 | 31.406 ms | 24.941 ms | 22.018 ms | 19.869 ms | 27.807 ms | 18.636 ms | 12.097 ms | 12.013 ms | — | — | 2.219 ms | 908.391 μs |
| det! tensor | Float32 512^3 | — | — | — | — | 200.939 ms | 124.801 ms | 104.149 ms | 103.596 ms | — | — | 9.408 ms | — |
| det! tensor | Float32 64^3 | 311.698 μs | 156.446 μs | 90.385 μs | 46.610 μs | 250.532 μs | 137.281 μs | 65.151 μs | 37.191 μs | — | — | 966.709 μs | 63.821 μs |
| det! tensor | Float64 128^3 | 6.978 ms | 5.547 ms | 4.539 ms | 4.120 ms | 3.985 ms | 2.439 ms | 1.672 ms | 1.625 ms | — | — | 1.460 ms | 270.074 μs |
| det! tensor | Float64 256^3 | 54.533 ms | 49.431 ms | 43.421 ms | 39.574 ms | 41.250 ms | 28.845 ms | 25.659 ms | 26.451 ms | — | — | 2.941 ms | 1.786 ms |
| det! tensor | Float64 512^3 | — | — | — | — | 381.984 ms | 239.026 ms | 206.983 ms | 207.743 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 401.294 μs | 190.520 μs | 104.582 μs | 60.228 μs | 252.803 μs | 129.602 μs | 66.360 μs | 42.080 μs | — | — | 1.071 ms | 72.870 μs |
| dot! vec.vec | Float32 128^3 | 2.818 ms | 1.667 ms | 1.238 ms | 1.100 ms | 2.464 ms | 1.254 ms | 624.637 μs | 323.563 μs | 538.855 μs | 2.430 ms | 1.239 ms | 113.921 μs |
| dot! vec.vec | Float32 256^3 | 23.922 ms | 17.102 ms | 15.070 ms | 13.902 ms | 30.274 ms | 13.136 ms | 8.198 ms | 8.119 ms | — | 9.651 ms | 2.506 ms | 634.637 μs |
| dot! vec.vec | Float32 512^3 | — | — | — | — | 196.402 ms | 97.485 ms | 75.424 ms | 75.268 ms | — | — | 11.342 ms | — |
| dot! vec.vec | Float32 64^3 | 335.368 μs | 211.988 μs | 104.493 μs | 58.821 μs | 310.243 μs | 159.971 μs | 81.201 μs | 44.461 μs | 112.901 μs | 1.663 ms | 1.107 ms | 60.341 μs |
| dot! vec.vec | Float64 128^3 | 4.591 ms | 3.737 ms | 3.113 ms | 2.841 ms | 3.440 ms | 1.737 ms | 886.270 μs | 573.165 μs | 618.906 μs | 2.505 ms | 1.223 ms | 204.243 μs |
| dot! vec.vec | Float64 256^3 | 39.083 ms | 34.593 ms | 29.176 ms | 26.807 ms | 36.264 ms | 22.504 ms | 18.471 ms | 19.748 ms | — | 9.784 ms | 2.819 ms | 1.207 ms |
| dot! vec.vec | Float64 512^3 | — | — | — | — | 226.381 ms | 154.071 ms | 149.076 ms | 159.028 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 345.663 μs | 200.428 μs | 105.506 μs | 63.063 μs | 317.663 μs | 159.571 μs | 81.361 μs | 44.610 μs | 127.611 μs | 1.656 ms | 1.019 ms | 59.821 μs |
| mul! tensor.vec | Float32 128^3 | 4.869 ms | 4.207 ms | 3.733 ms | 3.526 ms | 3.491 ms | 1.826 ms | 991.371 μs | 771.778 μs | 1.525 ms | 4.295 ms | 1.202 ms | 208.463 μs |
| mul! tensor.vec | Float32 256^3 | 48.044 ms | 39.433 ms | 37.017 ms | 34.956 ms | 43.068 ms | 29.483 ms | 22.109 ms | 22.008 ms | — | 16.892 ms | 2.504 ms | 1.324 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | 348.899 ms | 222.471 ms | 175.333 ms | 174.454 ms | — | — | 12.936 ms | — |
| mul! tensor.vec | Float32 64^3 | 444.763 μs | 233.734 μs | 123.888 μs | 72.240 μs | 372.223 μs | 214.202 μs | 107.522 μs | 59.561 μs | 255.702 μs | 1.882 ms | 1.051 ms | 67.100 μs |
| mul! tensor.vec | Float64 128^3 | 11.026 ms | 9.140 ms | 8.239 ms | 7.929 ms | 7.061 ms | 5.383 ms | 4.449 ms | 4.256 ms | 1.748 ms | 4.757 ms | 1.469 ms | 371.575 μs |
| mul! tensor.vec | Float64 256^3 | 87.198 ms | 79.322 ms | 74.695 ms | 70.590 ms | 57.713 ms | 51.357 ms | 44.307 ms | 43.405 ms | — | 17.818 ms | 3.896 ms | 2.557 ms |
| mul! tensor.vec | Float64 512^3 | — | — | — | — | 533.991 ms | 378.774 ms | 343.129 ms | 346.282 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 707.994 μs | 467.478 μs | 342.675 μs | 214.465 μs | 377.524 μs | 214.582 μs | 109.421 μs | 59.290 μs | 280.183 μs | 1.951 ms | 1.082 ms | 74.541 μs |
| norm! vec | Float32 128^3 | 769.125 μs | 596.350 μs | 464.500 μs | 346.463 μs | 225.323 μs | 116.271 μs | 62.990 μs | 51.760 μs | 411.304 μs | 2.110 ms | 1.077 ms | 86.131 μs |
| norm! vec | Float32 256^3 | 10.233 ms | 9.470 ms | 7.826 ms | 7.318 ms | 5.301 ms | 4.295 ms | 4.091 ms | 4.249 ms | — | 7.304 ms | 2.143 ms | 386.525 μs |
| norm! vec | Float32 512^3 | — | — | — | — | 52.653 ms | 44.996 ms | 46.122 ms | 46.517 ms | — | — | 7.958 ms | — |
| norm! vec | Float32 64^3 | 54.550 μs | 38.361 μs | 18.877 μs | 16.559 μs | 27.400 μs | 20.980 μs | 12.611 μs | 11.580 μs | 100.251 μs | 1.526 ms | 1.029 ms | 58.990 μs |
| norm! vec | Float64 128^3 | 2.145 ms | 1.888 ms | 1.468 ms | 1.343 ms | 487.265 μs | 254.962 μs | 130.682 μs | 101.921 μs | 463.344 μs | 1.434 ms | 1.433 ms | 173.042 μs |
| norm! vec | Float64 256^3 | 21.121 ms | 19.495 ms | 16.044 ms | 14.926 ms | 11.920 ms | 10.274 ms | 10.248 ms | 10.503 ms | — | 9.850 ms | 3.294 ms | 724.359 μs |
| norm! vec | Float64 512^3 | — | — | — | — | 97.639 ms | 90.073 ms | 91.357 ms | 92.839 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 160.946 μs | 89.288 μs | 50.186 μs | 32.246 μs | 56.440 μs | 35.150 μs | 21.090 μs | 15.800 μs | 101.231 μs | 1.681 ms | 1.117 ms | 60.290 μs |
| tr! tensor | Float32 128^3 | 761.345 μs | 568.788 μs | 445.551 μs | 330.323 μs | 214.702 μs | 113.151 μs | 59.821 μs | 50.380 μs | — | — | 1.021 ms | 85.431 μs |
| tr! tensor | Float32 256^3 | 10.200 ms | 9.364 ms | 7.653 ms | 7.051 ms | 5.147 ms | 4.460 ms | 4.285 ms | 4.361 ms | — | — | 1.859 ms | 394.344 μs |
| tr! tensor | Float32 512^3 | — | — | — | — | 51.458 ms | 45.117 ms | 46.267 ms | 46.860 ms | — | — | 8.577 ms | — |
| tr! tensor | Float32 64^3 | 53.859 μs | 32.010 μs | 15.661 μs | 13.252 μs | 27.490 μs | 18.600 μs | 10.840 μs | 9.390 μs | — | — | 1.108 ms | 68.110 μs |
| tr! tensor | Float64 128^3 | 2.148 ms | 1.860 ms | 1.419 ms | 1.287 ms | 457.195 μs | 239.273 μs | 131.402 μs | 101.801 μs | — | — | 1.153 ms | 119.872 μs |
| tr! tensor | Float64 256^3 | 20.837 ms | 19.133 ms | 15.676 ms | 14.741 ms | 11.735 ms | 10.586 ms | 10.531 ms | 10.762 ms | — | — | 2.035 ms | 727.419 μs |
| tr! tensor | Float64 512^3 | — | — | — | — | 95.574 ms | 91.160 ms | 92.651 ms | 93.818 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 107.326 μs | 60.816 μs | 34.249 μs | 25.132 μs | 53.730 μs | 32.540 μs | 18.760 μs | 13.670 μs | — | — | 1.004 ms | 58.041 μs |

## operators

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.563 ms | 2.816 ms | 1.518 ms | 1.187 ms | 3.203 ms | 1.652 ms | 834.190 μs | 422.744 μs | 697.807 μs | 2.544 ms | 1.114 ms | 90.972 μs |
| curl! vec->vec | Float32 256^3 | 44.228 ms | 22.765 ms | 17.273 ms | 16.586 ms | 27.208 ms | 13.422 ms | 8.555 ms | 8.571 ms | — | 10.865 ms | 1.562 ms | 587.487 μs |
| curl! vec->vec | Float32 512^3 | — | — | — | — | 210.958 ms | 112.992 ms | 81.970 ms | 83.550 ms | — | — | 6.384 ms | — |
| curl! vec->vec | Float32 64^3 | 716.357 μs | 359.757 μs | 184.052 μs | 97.080 μs | 424.824 μs | 218.492 μs | 110.472 μs | 59.210 μs | 182.902 μs | 1.646 ms | 1.026 ms | 56.251 μs |
| curl! vec->vec | Float64 128^3 | 5.768 ms | 4.055 ms | 3.544 ms | 3.406 ms | 3.672 ms | 1.858 ms | 987.181 μs | 519.585 μs | 824.588 μs | 3.153 ms | 1.535 ms | 198.083 μs |
| curl! vec->vec | Float64 256^3 | 45.976 ms | 37.130 ms | 35.281 ms | 33.988 ms | 33.268 ms | 20.453 ms | 19.332 ms | 21.030 ms | — | 13.647 ms | 3.147 ms | 1.133 ms |
| curl! vec->vec | Float64 512^3 | — | — | — | — | 246.925 ms | 166.374 ms | 162.480 ms | 165.773 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 682.082 μs | 349.886 μs | 179.375 μs | 96.404 μs | 461.274 μs | 228.373 μs | 118.061 μs | 61.670 μs | 186.242 μs | 1.786 ms | 1.155 ms | 77.961 μs |
| divergence! vec->scalar | Float32 128^3 | 3.459 ms | 1.388 ms | 719.152 μs | 410.599 μs | 3.362 ms | 1.110 ms | 557.826 μs | 290.203 μs | 326.353 μs | 1.957 ms | 1.144 ms | 86.281 μs |
| divergence! vec->scalar | Float32 256^3 | 27.702 ms | 11.228 ms | 8.938 ms | 8.164 ms | 26.590 ms | 8.842 ms | 4.512 ms | 4.162 ms | — | 5.523 ms | 1.734 ms | 397.924 μs |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | 210.847 ms | 70.642 ms | 46.211 ms | 46.802 ms | — | — | 6.985 ms | — |
| divergence! vec->scalar | Float32 64^3 | 429.065 μs | 175.991 μs | 92.564 μs | 51.552 μs | 434.375 μs | 152.381 μs | 77.560 μs | 42.480 μs | 93.900 μs | 1.537 ms | 971.404 μs | 61.260 μs |
| divergence! vec->scalar | Float64 128^3 | 3.776 ms | 1.997 ms | 1.631 ms | 1.418 ms | 3.343 ms | 1.061 ms | 536.196 μs | 280.153 μs | 407.644 μs | 2.306 ms | 1.190 ms | 134.092 μs |
| divergence! vec->scalar | Float64 256^3 | 29.707 ms | 20.780 ms | 17.228 ms | 15.845 ms | 26.897 ms | 11.138 ms | 10.552 ms | 10.280 ms | — | 7.090 ms | 2.578 ms | 743.438 μs |
| divergence! vec->scalar | Float64 512^3 | — | — | — | — | 217.286 ms | 93.090 ms | 92.310 ms | 92.951 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 427.757 μs | 162.608 μs | 86.164 μs | 56.200 μs | 447.795 μs | 138.812 μs | 74.881 μs | 39.560 μs | 103.111 μs | 344.869 μs | 982.625 μs | 67.200 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.380 ms | 1.794 ms | 939.597 μs | 638.609 μs | 3.732 ms | 1.324 ms | 672.238 μs | 349.114 μs | — | — | 1.230 ms | 89.511 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 34.856 ms | 14.470 ms | 11.248 ms | 10.478 ms | 29.536 ms | 10.427 ms | 5.530 ms | 5.494 ms | — | — | 2.109 ms | 480.555 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | — | — | — | — | 234.985 ms | 82.548 ms | 56.267 ms | 56.685 ms | — | — | 7.652 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 565.306 μs | 232.569 μs | 124.846 μs | 75.264 μs | 484.015 μs | 181.432 μs | 94.191 μs | 53.381 μs | — | — | 1.103 ms | 66.290 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.856 ms | 2.607 ms | 2.133 ms | 1.908 ms | 3.563 ms | 1.341 ms | 670.287 μs | 369.273 μs | — | — | 1.365 ms | 191.013 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 38.410 ms | 25.393 ms | 21.232 ms | 19.545 ms | 29.570 ms | 13.820 ms | 12.977 ms | 12.922 ms | — | — | 2.922 ms | 909.931 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | — | — | — | — | 233.905 ms | 114.432 ms | 111.909 ms | 112.783 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 526.810 μs | 214.114 μs | 118.174 μs | 73.431 μs | 489.355 μs | 176.832 μs | 94.431 μs | 52.481 μs | — | — | 1.163 ms | 71.931 μs |
| gradient! scalar->vec | Float32 128^3 | 3.171 ms | 1.634 ms | 868.228 μs | 517.919 μs | 1.960 ms | 973.459 μs | 488.995 μs | 252.522 μs | 560.525 μs | 2.377 ms | 1.076 ms | 82.271 μs |
| gradient! scalar->vec | Float32 256^3 | 25.471 ms | 14.225 ms | 12.867 ms | 12.677 ms | 15.888 ms | 7.836 ms | 5.697 ms | 5.643 ms | — | 7.929 ms | 1.569 ms | 438.575 μs |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | 125.589 ms | 65.702 ms | 63.720 ms | 64.254 ms | — | — | 4.394 ms | — |
| gradient! scalar->vec | Float32 64^3 | 406.927 μs | 214.026 μs | 107.016 μs | 58.847 μs | 248.053 μs | 126.611 μs | 63.961 μs | 35.120 μs | 133.261 μs | 1.681 ms | 1.016 ms | 75.260 μs |
| gradient! scalar->vec | Float64 128^3 | 3.343 ms | 2.726 ms | 2.429 ms | 2.311 ms | 2.064 ms | 991.759 μs | 497.046 μs | 254.142 μs | 605.225 μs | 2.717 ms | 1.313 ms | 175.883 μs |
| gradient! scalar->vec | Float64 256^3 | 30.647 ms | 28.292 ms | 27.068 ms | 26.184 ms | 20.172 ms | 14.834 ms | 14.018 ms | 14.127 ms | — | 10.338 ms | 2.498 ms | 800.889 μs |
| gradient! scalar->vec | Float64 512^3 | — | — | — | — | 157.261 ms | 128.770 ms | 126.854 ms | 128.109 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 369.398 μs | 180.410 μs | 94.394 μs | 57.961 μs | 259.643 μs | 127.001 μs | 64.581 μs | 34.380 μs | 153.172 μs | 1.872 ms | 1.022 ms | 78.281 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.356 ms | 2.246 ms | 1.395 ms | 1.190 ms | 4.520 ms | 2.291 ms | 1.150 ms | 584.275 μs | 1.480 ms | 4.174 ms | 1.196 ms | 96.641 μs |
| helmholtz! vec->vec | Float32 256^3 | 34.749 ms | 19.010 ms | 17.135 ms | 16.567 ms | 36.298 ms | 18.200 ms | 9.313 ms | 8.586 ms | — | 16.637 ms | 1.739 ms | 590.487 μs |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | 281.602 ms | 146.058 ms | 82.927 ms | 83.822 ms | — | — | 6.606 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 548.457 μs | 284.606 μs | 144.893 μs | 78.603 μs | 616.166 μs | 313.054 μs | 159.182 μs | 83.171 μs | 286.333 μs | 1.935 ms | 1.057 ms | 60.861 μs |
| helmholtz! vec->vec | Float64 128^3 | 5.174 ms | 3.980 ms | 3.534 ms | 3.403 ms | 5.218 ms | 2.634 ms | 1.351 ms | 681.376 μs | 1.802 ms | 5.921 ms | 1.598 ms | 232.383 μs |
| helmholtz! vec->vec | Float64 256^3 | 42.543 ms | 37.205 ms | 35.258 ms | 34.169 ms | 45.605 ms | 23.292 ms | 19.540 ms | 19.657 ms | — | 18.240 ms | 3.879 ms | 1.322 ms |
| helmholtz! vec->vec | Float64 512^3 | — | — | — | — | 347.765 ms | 194.912 ms | 163.393 ms | 167.703 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 597.310 μs | 302.325 μs | 156.478 μs | 86.754 μs | 716.778 μs | 360.424 μs | 184.241 μs | 94.291 μs | 342.613 μs | 2.260 ms | 1.218 ms | 84.351 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 5.969 ms | 3.072 ms | 1.760 ms | 1.484 ms | 5.097 ms | 2.585 ms | 1.289 ms | 660.896 μs | — | — | 1.065 ms | 119.671 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 47.215 ms | 24.408 ms | 19.149 ms | 18.463 ms | 42.087 ms | 20.950 ms | 10.599 ms | 10.002 ms | — | — | 1.706 ms | 671.968 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | — | — | — | — | 325.709 ms | 171.093 ms | 93.646 ms | 93.578 ms | — | — | 7.390 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 777.668 μs | 395.053 μs | 199.917 μs | 106.426 μs | 687.207 μs | 349.564 μs | 174.953 μs | 91.271 μs | — | — | 1.107 ms | 67.620 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 6.715 ms | 4.564 ms | 4.066 ms | 3.930 ms | 5.944 ms | 2.987 ms | 1.540 ms | 815.547 μs | — | — | 1.683 ms | 308.384 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 53.686 ms | 41.559 ms | 39.474 ms | 37.987 ms | 53.046 ms | 27.835 ms | 22.220 ms | 23.509 ms | — | — | 4.462 ms | 1.695 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | — | — | — | — | 398.066 ms | 229.465 ms | 183.852 ms | 187.381 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 823.542 μs | 407.775 μs | 211.369 μs | 112.599 μs | 776.868 μs | 394.494 μs | 199.152 μs | 102.681 μs | — | — | 964.417 μs | 93.280 μs |
| laplacian! scalar | Float32 128^3 | 1.995 ms | 637.051 μs | 333.952 μs | 174.755 μs | 2.150 ms | 492.446 μs | 249.742 μs | 129.942 μs | 265.103 μs | 1.910 ms | 1.181 ms | 82.041 μs |
| laplacian! scalar | Float32 256^3 | 16.265 ms | 5.857 ms | 4.946 ms | 4.090 ms | 17.081 ms | 3.885 ms | 1.952 ms | 1.196 ms | — | 5.490 ms | 1.688 ms | 253.963 μs |
| laplacian! scalar | Float32 512^3 | — | — | — | — | 136.423 ms | 31.716 ms | 26.141 ms | 27.582 ms | — | — | 5.262 ms | — |
| laplacian! scalar | Float32 64^3 | 254.231 μs | 88.449 μs | 48.617 μs | 30.784 μs | 274.853 μs | 69.130 μs | 36.331 μs | 22.130 μs | 83.431 μs | 1.563 ms | 957.239 μs | 52.001 μs |
| laplacian! scalar | Float64 128^3 | 2.194 ms | 836.610 μs | 621.697 μs | 443.246 μs | 2.202 ms | 527.195 μs | 267.723 μs | 140.342 μs | 278.082 μs | 1.957 ms | 1.174 ms | 77.931 μs |
| laplacian! scalar | Float64 256^3 | 17.415 ms | 11.853 ms | 11.367 ms | 10.718 ms | 17.664 ms | 5.236 ms | 4.769 ms | 4.828 ms | — | 4.740 ms | 1.795 ms | 412.744 μs |
| laplacian! scalar | Float64 512^3 | — | — | — | — | 141.317 ms | 54.492 ms | 53.657 ms | 54.940 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 274.735 μs | 92.475 μs | 50.520 μs | 33.814 μs | 282.643 μs | 72.971 μs | 39.710 μs | 23.500 μs | 84.420 μs | 1.586 ms | 1.058 ms | 55.761 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.744 ms | 6.053 ms | 4.299 ms | 4.158 ms | 9.580 ms | 4.840 ms | 2.435 ms | 1.236 ms | — | — | 1.173 ms | 218.243 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 91.576 ms | 51.155 ms | 42.761 ms | 41.789 ms | 82.054 ms | 42.823 ms | 25.756 ms | 24.160 ms | — | — | 2.615 ms | 1.196 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | — | — | — | — | 640.245 ms | 346.382 ms | 205.949 ms | 197.696 ms | — | — | 14.783 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.545 ms | 748.571 μs | 380.838 μs | 200.198 μs | 1.215 ms | 624.876 μs | 309.594 μs | 158.022 μs | — | — | 1.040 ms | 69.000 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 13.544 ms | 10.177 ms | 9.568 ms | 9.493 ms | 10.635 ms | 5.734 ms | 3.709 ms | 3.768 ms | — | — | 1.627 ms | 355.604 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 111.938 ms | 89.917 ms | 86.753 ms | 84.454 ms | 90.816 ms | 52.548 ms | 48.753 ms | 49.651 ms | — | — | 4.370 ms | 2.299 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | — | — | — | — | 685.334 ms | 440.168 ms | 387.147 ms | 395.279 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.592 ms | 793.494 μs | 412.431 μs | 225.260 μs | 1.273 ms | 645.096 μs | 323.504 μs | 166.382 μs | — | — | 1.192 ms | 101.521 μs |

## convolution

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.806 ms | 491.585 μs | 412.889 μs | 328.085 μs | 1.361 ms | 300.363 μs | 154.651 μs | 83.421 μs | 296.642 μs | 1.855 ms | 991.293 μs | 134.442 μs |
| assignment_window | Float32 256^3 | 26.854 ms | 10.564 ms | 3.781 ms | 3.408 ms | 18.023 ms | 6.962 ms | 2.102 ms | 2.013 ms | — | 3.952 ms | 1.684 ms | 271.043 μs |
| assignment_window | Float32 512^3 | — | — | — | — | 150.143 ms | 54.426 ms | 32.759 ms | 21.780 ms | — | — | 5.043 ms | — |
| assignment_window | Float32 64^3 | 228.446 μs | 64.288 μs | 37.124 μs | 31.428 μs | 176.112 μs | 44.690 μs | 25.351 μs | 16.840 μs | 138.651 μs | 1.640 ms | 1.027 ms | 127.492 μs |
| assignment_window | Float64 128^3 | 1.904 ms | 993.279 μs | 813.341 μs | 542.612 μs | 1.544 ms | 392.794 μs | 365.324 μs | 321.743 μs | 306.863 μs | 1.901 ms | 1.136 ms | 146.542 μs |
| assignment_window | Float64 256^3 | 39.723 ms | 17.502 ms | 9.461 ms | 6.134 ms | 27.898 ms | 11.831 ms | 7.322 ms | 4.386 ms | — | 4.237 ms | 1.784 ms | 293.573 μs |
| assignment_window | Float64 512^3 | — | — | — | — | 220.058 ms | 92.659 ms | 59.236 ms | 43.545 ms | — | — | — | — |
| assignment_window | Float64 64^3 | 237.894 μs | 67.685 μs | 49.135 μs | 56.957 μs | 199.382 μs | 47.460 μs | 26.710 μs | 17.850 μs | 141.232 μs | 1.542 ms | 1.162 ms | 114.431 μs |
| combine!∘kernel vector | Float32 128^3 | 4.009 ms | 2.205 ms | 1.604 ms | 1.462 ms | 3.149 ms | 1.547 ms | 776.849 μs | 416.964 μs | — | — | 957.518 μs | 133.091 μs |
| combine!∘kernel vector | Float32 256^3 | 32.580 ms | 21.070 ms | 19.619 ms | 18.564 ms | 27.839 ms | 14.121 ms | 9.869 ms | 9.970 ms | — | — | 1.958 ms | 924.721 μs |
| combine!∘kernel vector | Float32 512^3 | — | — | — | — | 241.620 ms | 135.407 ms | 92.212 ms | 93.088 ms | — | — | 8.534 ms | — |
| combine!∘kernel vector | Float32 64^3 | 567.697 μs | 270.573 μs | 139.400 μs | 75.641 μs | 420.404 μs | 207.282 μs | 105.621 μs | 56.570 μs | — | — | 1.101 ms | 78.461 μs |
| combine!∘kernel vector | Float64 128^3 | 5.492 ms | 4.579 ms | 4.197 ms | 3.916 ms | 3.687 ms | 2.052 ms | 1.091 ms | 752.867 μs | — | — | 1.469 ms | 294.554 μs |
| combine!∘kernel vector | Float64 256^3 | 47.930 ms | 42.048 ms | 39.834 ms | 37.825 ms | 34.145 ms | 23.060 ms | 21.962 ms | 23.351 ms | — | — | 3.008 ms | 1.792 ms |
| combine!∘kernel vector | Float64 512^3 | — | — | — | — | 256.016 ms | 186.416 ms | 184.174 ms | 185.285 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 507.340 μs | 277.943 μs | 142.570 μs | 88.232 μs | 378.834 μs | 226.922 μs | 118.331 μs | 63.720 μs | — | — | 1.001 ms | 80.550 μs |
| convolve! scalar | Float32 128^3 | 1.585 ms | 310.214 μs | 205.518 μs | 104.796 μs | 920.419 μs | 108.071 μs | 56.900 μs | 36.420 μs | 220.032 μs | 1.755 ms | 877.910 μs | 63.601 μs |
| convolve! scalar | Float32 256^3 | 13.110 ms | 7.746 ms | 7.266 ms | 6.801 ms | 7.589 ms | 2.883 ms | 2.643 ms | 2.733 ms | — | 3.659 ms | 1.656 ms | 312.854 μs |
| convolve! scalar | Float32 512^3 | — | — | — | — | 62.006 ms | 37.388 ms | 36.530 ms | 36.849 ms | — | — | 4.192 ms | — |
| convolve! scalar | Float32 64^3 | 202.017 μs | 40.433 μs | 14.196 μs | 13.711 μs | 116.741 μs | 16.490 μs | 9.710 μs | 7.580 μs | 78.951 μs | 1.480 ms | 1.035 ms | 57.290 μs |
| convolve! scalar | Float64 128^3 | 1.786 ms | 1.359 ms | 1.166 ms | 1.025 ms | 997.571 μs | 172.471 μs | 93.971 μs | 71.861 μs | 302.553 μs | 1.784 ms | 1.135 ms | 90.291 μs |
| convolve! scalar | Float64 256^3 | 18.094 ms | 16.196 ms | 15.246 ms | 14.295 ms | 10.898 ms | 7.861 ms | 7.617 ms | 7.770 ms | — | 4.442 ms | 2.019 ms | 575.286 μs |
| convolve! scalar | Float64 512^3 | — | — | — | — | 89.577 ms | 73.921 ms | 73.925 ms | 74.184 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 180.292 μs | 51.056 μs | 25.989 μs | 18.807 μs | 128.572 μs | 28.980 μs | 14.080 μs | 10.640 μs | 78.591 μs | 1.618 ms | 951.395 μs | 55.431 μs |
| convolve! vector | Float32 128^3 | 2.649 ms | 1.833 ms | 1.554 ms | 1.468 ms | 2.094 ms | 1.100 ms | 548.955 μs | 299.313 μs | 731.727 μs | 2.557 ms | 921.484 μs | 108.091 μs |
| convolve! vector | Float32 256^3 | 23.285 ms | 20.504 ms | 19.089 ms | 18.494 ms | 20.326 ms | 11.003 ms | 9.834 ms | 9.916 ms | — | 10.821 ms | 1.185 ms | 681.018 μs |
| convolve! vector | Float32 512^3 | — | — | — | — | 177.069 ms | 94.434 ms | 92.113 ms | 92.519 ms | — | — | 6.065 ms | — |
| convolve! vector | Float32 64^3 | 360.462 μs | 174.413 μs | 90.623 μs | 50.329 μs | 272.252 μs | 146.602 μs | 74.590 μs | 40.140 μs | 161.751 μs | 1.595 ms | 1.094 ms | 70.901 μs |
| convolve! vector | Float64 128^3 | 4.985 ms | 4.563 ms | 4.113 ms | 3.934 ms | 2.648 ms | 1.550 ms | 877.130 μs | 748.577 μs | 792.657 μs | 2.910 ms | 1.329 ms | 227.133 μs |
| convolve! vector | Float64 256^3 | 44.348 ms | 41.696 ms | 39.335 ms | 37.806 ms | 30.552 ms | 22.792 ms | 21.925 ms | 23.340 ms | — | 12.297 ms | 2.365 ms | 1.302 ms |
| convolve! vector | Float64 512^3 | — | — | — | — | 223.020 ms | 184.776 ms | 183.563 ms | 184.580 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 284.540 μs | 161.378 μs | 87.704 μs | 58.337 μs | 217.852 μs | 132.852 μs | 72.700 μs | 39.621 μs | 167.451 μs | 1.655 ms | 1.102 ms | 74.220 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.581 ms | 2.461 ms | 1.663 ms | 924.578 μs | 3.815 ms | 1.637 ms | 869.730 μs | 453.674 μs | — | — | 1.058 ms | 73.720 μs |
| exponential_convolve! scalar | Float32 256^3 | 33.178 ms | 13.132 ms | 7.147 ms | 5.350 ms | 28.508 ms | 11.862 ms | 5.970 ms | 3.107 ms | — | — | 1.651 ms | 249.413 μs |
| exponential_convolve! scalar | Float32 512^3 | — | — | — | — | 225.346 ms | 92.580 ms | 46.442 ms | 27.473 ms | — | — | 5.951 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 2.194 ms | 1.061 ms | 557.489 μs | 300.107 μs | 775.658 μs | 345.654 μs | 170.292 μs | 99.191 μs | — | — | 999.111 μs | 62.701 μs |
| exponential_convolve! scalar | Float64 128^3 | 8.229 ms | 3.741 ms | 2.315 ms | 1.542 ms | 5.829 ms | 2.532 ms | 1.271 ms | 659.776 μs | — | — | 1.328 ms | 129.502 μs |
| exponential_convolve! scalar | Float64 256^3 | 53.550 ms | 24.084 ms | 13.857 ms | 10.934 ms | 41.019 ms | 17.691 ms | 9.044 ms | 4.999 ms | — | — | 2.622 ms | 705.918 μs |
| exponential_convolve! scalar | Float64 512^3 | — | — | — | — | 312.730 ms | 134.163 ms | 69.681 ms | 54.731 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 733.246 μs | 329.596 μs | 170.988 μs | 98.234 μs | 700.417 μs | 309.533 μs | 158.721 μs | 84.260 μs | — | — | 986.434 μs | 62.870 μs |
| exponential_convolve! vector | Float32 128^3 | 18.422 ms | 8.966 ms | 5.849 ms | 3.164 ms | 13.386 ms | 6.392 ms | 3.633 ms | 1.713 ms | — | — | 1.208 ms | 134.301 μs |
| exponential_convolve! vector | Float32 256^3 | 111.474 ms | 52.874 ms | 28.318 ms | 18.651 ms | 101.617 ms | 47.162 ms | 23.779 ms | 12.430 ms | — | — | 3.202 ms | 701.227 μs |
| exponential_convolve! vector | Float32 512^3 | — | — | — | — | 833.980 ms | 371.941 ms | 186.136 ms | 97.797 ms | — | — | 14.658 ms | — |
| exponential_convolve! vector | Float32 64^3 | 6.905 ms | 3.428 ms | 1.789 ms | 947.317 μs | 2.259 ms | 1.219 ms | 578.537 μs | 332.853 μs | — | — | 1.051 ms | 75.871 μs |
| exponential_convolve! vector | Float64 128^3 | 27.272 ms | 12.873 ms | 7.776 ms | 4.946 ms | 20.029 ms | 9.076 ms | 4.583 ms | 2.391 ms | — | — | 1.842 ms | 291.874 μs |
| exponential_convolve! vector | Float64 256^3 | 178.881 ms | 85.241 ms | 47.532 ms | 34.357 ms | 144.067 ms | 63.915 ms | 32.981 ms | 19.357 ms | — | — | 5.713 ms | 1.965 ms |
| exponential_convolve! vector | Float64 512^3 | — | — | — | — | 1.111 s | 512.433 ms | 256.095 ms | 164.820 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.493 ms | 1.168 ms | 591.526 μs | 332.229 μs | 2.459 ms | 1.102 ms | 552.615 μs | 283.652 μs | — | — | 1.060 ms | 81.801 μs |
| spectral_band | Float32 128^3 | 4.090 ms | 1.619 ms | 817.818 μs | 438.346 μs | 3.856 ms | 1.365 ms | 686.847 μs | 348.073 μs | 334.154 μs | 2.050 ms | 1.005 ms | 97.391 μs |
| spectral_band | Float32 256^3 | 44.323 ms | 19.362 ms | 6.350 ms | 5.399 ms | 39.014 ms | 15.953 ms | 5.429 ms | 2.741 ms | — | 6.344 ms | 1.755 ms | 269.943 μs |
| spectral_band | Float32 512^3 | — | — | — | — | 314.469 ms | 125.228 ms | 64.896 ms | 32.751 ms | — | — | 7.315 ms | — |
| spectral_band | Float32 64^3 | 511.515 μs | 217.387 μs | 112.762 μs | 63.175 μs | 492.845 μs | 179.682 μs | 92.471 μs | 49.870 μs | 106.071 μs | 1.537 ms | 1.000 ms | 80.151 μs |
| spectral_band | Float64 128^3 | 4.255 ms | 1.594 ms | 972.873 μs | 726.675 μs | 3.969 ms | 1.378 ms | 693.078 μs | 357.014 μs | 361.113 μs | 2.105 ms | 1.221 ms | 107.612 μs |
| spectral_band | Float64 256^3 | 56.833 ms | 26.310 ms | 13.507 ms | 8.107 ms | 48.049 ms | 19.562 ms | 10.115 ms | 4.252 ms | — | 5.611 ms | 2.014 ms | 298.844 μs |
| spectral_band | Float64 512^3 | — | — | — | — | 394.593 ms | 153.201 ms | 79.445 ms | 45.161 ms | — | — | — | — |
| spectral_band | Float64 64^3 | 529.728 μs | 213.257 μs | 104.881 μs | 68.680 μs | 504.155 μs | 181.802 μs | 93.401 μs | 50.370 μs | 110.411 μs | 1.651 ms | 866.015 μs | 69.180 μs |
| spectral_cutoff | Float32 128^3 | 4.110 ms | 1.620 ms | 818.057 μs | 439.049 μs | 3.858 ms | 1.364 ms | 685.208 μs | 349.213 μs | 331.623 μs | 2.046 ms | 1.093 ms | 102.101 μs |
| spectral_cutoff | Float32 256^3 | 44.369 ms | 19.371 ms | 6.344 ms | 5.427 ms | 38.752 ms | 15.905 ms | 5.418 ms | 2.738 ms | — | 5.403 ms | 1.983 ms | 275.163 μs |
| spectral_cutoff | Float32 512^3 | — | — | — | — | 314.255 ms | 125.415 ms | 65.606 ms | 32.848 ms | — | — | 6.140 ms | — |
| spectral_cutoff | Float32 64^3 | 524.714 μs | 216.291 μs | 112.468 μs | 63.401 μs | 491.925 μs | 180.001 μs | 92.501 μs | 49.921 μs | 108.881 μs | 1.625 ms | 1.105 ms | 83.271 μs |
| spectral_cutoff | Float64 128^3 | 4.248 ms | 1.585 ms | 972.493 μs | 646.013 μs | 3.966 ms | 1.379 ms | 693.498 μs | 360.543 μs | 351.793 μs | 2.120 ms | 1.131 ms | 104.231 μs |
| spectral_cutoff | Float64 256^3 | 56.962 ms | 26.321 ms | 13.386 ms | 7.887 ms | 47.658 ms | 19.436 ms | 10.163 ms | 4.213 ms | — | 5.621 ms | 2.006 ms | 300.624 μs |
| spectral_cutoff | Float64 512^3 | — | — | — | — | 391.369 ms | 153.734 ms | 80.140 ms | 45.145 ms | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 532.338 μs | 210.978 μs | 104.816 μs | 67.969 μs | 505.175 μs | 181.792 μs | 94.040 μs | 50.490 μs | 117.711 μs | 1.647 ms | 1.006 ms | 72.781 μs |
| squared_wavenumber_field | Float32 128^3 | 1.784 ms | 481.642 μs | 430.492 μs | 321.444 μs | 1.375 ms | 296.254 μs | 150.622 μs | 79.120 μs | 262.463 μs | 1.824 ms | 961.813 μs | 84.721 μs |
| squared_wavenumber_field | Float32 256^3 | 26.599 ms | 10.498 ms | 3.812 ms | 3.421 ms | 18.199 ms | 7.016 ms | 2.032 ms | 1.675 ms | — | 3.812 ms | 1.541 ms | 221.563 μs |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | 151.875 ms | 54.583 ms | 32.704 ms | 21.584 ms | — | — | 4.991 ms | — |
| squared_wavenumber_field | Float32 64^3 | 225.854 μs | 60.775 μs | 34.018 μs | 25.356 μs | 176.631 μs | 41.950 μs | 22.720 μs | 14.151 μs | 91.321 μs | 1.517 ms | 954.784 μs | 78.972 μs |
| squared_wavenumber_field | Float64 128^3 | 1.919 ms | 988.789 μs | 820.982 μs | 493.981 μs | 1.420 ms | 425.364 μs | 347.304 μs | 323.592 μs | 264.163 μs | 1.805 ms | 1.079 ms | 94.861 μs |
| squared_wavenumber_field | Float64 256^3 | 39.741 ms | 17.593 ms | 9.491 ms | 6.179 ms | 28.059 ms | 11.818 ms | 7.257 ms | 4.368 ms | — | 4.151 ms | 1.758 ms | 252.183 μs |
| squared_wavenumber_field | Float64 512^3 | — | — | — | — | 219.319 ms | 92.814 ms | 59.240 ms | 42.975 ms | — | — | — | — |
| squared_wavenumber_field | Float64 64^3 | 231.508 μs | 69.587 μs | 53.275 μs | 49.029 μs | 182.112 μs | 43.460 μs | 23.890 μs | 14.300 μs | 88.931 μs | 1.612 ms | 1.059 ms | 65.281 μs |
| translation_kernel | Float32 128^3 | 1.802 ms | 784.099 μs | 446.968 μs | 323.818 μs | 1.536 ms | 447.655 μs | 227.083 μs | 118.971 μs | — | — | 1.218 ms | 112.821 μs |
| translation_kernel | Float32 256^3 | 26.736 ms | 13.192 ms | 3.964 ms | 4.024 ms | 19.566 ms | 8.290 ms | 2.117 ms | 2.019 ms | — | — | 1.653 ms | 255.093 μs |
| translation_kernel | Float32 512^3 | — | — | — | — | 167.737 ms | 65.912 ms | 35.321 ms | 23.073 ms | — | — | 5.084 ms | — |
| translation_kernel | Float32 64^3 | 233.144 μs | 103.112 μs | 55.846 μs | 35.753 μs | 197.472 μs | 60.931 μs | 32.780 μs | 20.060 μs | — | — | 1.138 ms | 104.771 μs |
| translation_kernel | Float64 128^3 | 1.838 ms | 992.241 μs | 755.760 μs | 525.278 μs | 1.451 ms | 457.825 μs | 282.373 μs | 324.903 μs | — | — | 1.338 ms | 146.012 μs |
| translation_kernel | Float64 256^3 | 39.684 ms | 19.890 ms | 10.384 ms | 6.489 ms | 28.317 ms | 13.159 ms | 7.687 ms | 4.347 ms | — | — | 2.213 ms | 452.685 μs |
| translation_kernel | Float64 512^3 | — | — | — | — | 218.222 ms | 103.214 ms | 63.170 ms | 44.004 ms | — | — | — | — |
| translation_kernel | Float64 64^3 | 232.023 μs | 105.782 μs | 58.775 μs | 53.360 μs | 187.331 μs | 62.590 μs | 33.550 μs | 20.820 μs | — | — | 1.188 ms | 100.811 μs |

## transfer

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.527 ms | 13.686 ms | 7.327 ms | 5.053 ms | 21.115 ms | 11.027 ms | 5.946 ms | 3.423 ms | 2.280 ms | 4.864 ms | 1.343 ms | 202.263 μs |
| anterpolate! CatmullRom | Float32 256^3 | 388.697 ms | 203.898 ms | 109.445 ms | 66.862 ms | 173.277 ms | 88.950 ms | 45.022 ms | 23.951 ms | — | 17.932 ms | 4.044 ms | 2.880 ms |
| anterpolate! CatmullRom | Float32 512^3 | — | — | — | — | 2.943 s | 1.499 s | 783.147 ms | 441.685 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.227 ms | 1.845 ms | 1.202 ms | 861.570 μs | 2.523 ms | 1.450 ms | 932.021 μs | 652.876 μs | 116.972 μs | 2.057 ms | 1.220 ms | 105.992 μs |
| anterpolate! CatmullRom | Float64 128^3 | 29.388 ms | 14.789 ms | 7.580 ms | 4.639 ms | 22.060 ms | 11.591 ms | 6.148 ms | 3.553 ms | 2.691 ms | 4.862 ms | 1.628 ms | 244.363 μs |
| anterpolate! CatmullRom | Float64 256^3 | 509.022 ms | 265.304 ms | 148.918 ms | 105.208 ms | 263.455 ms | 130.406 ms | 67.722 ms | 35.466 ms | — | 19.810 ms | 4.795 ms | 4.666 ms |
| anterpolate! CatmullRom | Float64 512^3 | — | — | — | — | 3.362 s | 1.737 s | 928.917 ms | 515.890 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.342 ms | 1.895 ms | 1.240 ms | 901.735 μs | 2.530 ms | 1.499 ms | 965.789 μs | 695.486 μs | 185.312 μs | 2.004 ms | 1.201 ms | 117.601 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 197.724 ms | 100.160 ms | 50.870 ms | 28.829 ms | 159.887 ms | 80.537 ms | 40.603 ms | 21.680 ms | 12.241 ms | 15.478 ms | 4.182 ms | 983.072 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.224 s | 1.190 s | 675.994 ms | 473.187 ms | 1.286 s | 643.816 ms | 322.030 ms | 164.797 ms | — | 48.567 ms | 18.203 ms | 14.982 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 11.796 s | 5.944 s | 3.081 s | 1.649 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.351 ms | 13.320 ms | 8.145 ms | 5.585 ms | 19.873 ms | 10.618 ms | 6.460 ms | 4.343 ms | 486.825 μs | 5.959 ms | 2.191 ms | 318.094 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 207.874 ms | 105.028 ms | 52.601 ms | 29.748 ms | 160.790 ms | 80.615 ms | 40.562 ms | 21.687 ms | 13.808 ms | 16.564 ms | 4.883 ms | 1.174 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.714 s | 1.432 s | 895.238 ms | 635.918 ms | 1.402 s | 697.115 ms | 354.181 ms | 179.349 ms | — | 66.043 ms | 28.833 ms | 24.239 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 12.795 s | 6.538 s | 3.419 s | 2.083 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.930 ms | 13.237 ms | 8.291 ms | 5.701 ms | 19.961 ms | 10.749 ms | 6.590 ms | 4.473 ms | 825.268 μs | 5.503 ms | 2.720 ms | 333.433 μs |
| anterpolate! NUFFT | Float32 128^3 | 418.683 ms | 236.019 ms | 150.990 ms | 120.239 ms | 369.698 ms | 193.018 ms | 110.791 ms | 59.706 ms | 20.177 ms | 18.762 ms | 5.604 ms | 2.762 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.389 s | 2.457 s | 1.498 s | 1.112 s | 3.783 s | 2.000 s | 1.106 s | 671.419 ms | — | 120.799 ms | 32.967 ms | 28.407 ms |
| anterpolate! NUFFT | Float32 512^3 | — | — | — | — | 30.987 s | 16.404 s | 9.048 s | 5.464 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 33.174 ms | 17.791 ms | 11.377 ms | 8.625 ms | 27.190 ms | 14.323 ms | 8.560 ms | 5.852 ms | 1.989 ms | 6.296 ms | 2.380 ms | 431.207 μs |
| anterpolate! NUFFT | Float64 128^3 | 558.144 ms | 327.399 ms | 219.207 ms | 181.378 ms | 424.578 ms | 238.994 ms | 142.939 ms | 89.947 ms | 30.358 ms | 22.503 ms | 10.016 ms | 6.537 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.118 s | 3.019 s | 1.961 s | 1.573 s | 3.659 s | 2.028 s | 1.235 s | 877.546 ms | — | 160.735 ms | 70.065 ms | 58.232 ms |
| anterpolate! NUFFT | Float64 512^3 | — | — | — | — | 39.739 s | 21.890 s | 12.669 s | 8.232 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 38.442 ms | 21.434 ms | 14.460 ms | 10.951 ms | 33.478 ms | 17.894 ms | 10.588 ms | 7.525 ms | 3.892 ms | 8.203 ms | 3.612 ms | 818.608 μs |
| anterpolate! trilinear | Float32 128^3 | 4.676 ms | 2.264 ms | 1.333 ms | 1.123 ms | 4.806 ms | 2.580 ms | 1.442 ms | 862.608 μs | 460.884 μs | 2.018 ms | 990.949 μs | 81.071 μs |
| anterpolate! trilinear | Float32 256^3 | 81.283 ms | 44.478 ms | 26.370 ms | 19.374 ms | 41.580 ms | 21.844 ms | 11.651 ms | 6.722 ms | — | 6.631 ms | 1.780 ms | 730.828 μs |
| anterpolate! trilinear | Float32 512^3 | — | — | — | — | 737.978 ms | 379.590 ms | 202.481 ms | 117.586 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 491.295 μs | 326.076 μs | 212.641 μs | 170.751 μs | 370.024 μs | 229.472 μs | 174.322 μs | 126.051 μs | 70.080 μs | 1.565 ms | 1.061 ms | 78.742 μs |
| anterpolate! trilinear | Float64 128^3 | 5.375 ms | 2.782 ms | 1.518 ms | 1.081 ms | 6.319 ms | 3.294 ms | 1.858 ms | 1.168 ms | 596.666 μs | 1.980 ms | 1.202 ms | 98.471 μs |
| anterpolate! trilinear | Float64 256^3 | 92.422 ms | 52.078 ms | 33.510 ms | 27.472 ms | 71.912 ms | 36.546 ms | 19.701 ms | 11.100 ms | — | 6.838 ms | 1.761 ms | 1.111 ms |
| anterpolate! trilinear | Float64 512^3 | — | — | — | — | 778.642 ms | 411.449 ms | 221.082 ms | 126.073 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 516.992 μs | 339.618 μs | 242.073 μs | 194.516 μs | 379.594 μs | 240.113 μs | 178.542 μs | 133.851 μs | 83.721 μs | 1.554 ms | 936.908 μs | 79.841 μs |
| interpolate! CatmullRom | Float32 128^3 | 11.514 ms | 5.878 ms | 2.959 ms | 1.620 ms | 5.461 ms | 2.795 ms | 1.387 ms | 735.726 μs | 972.889 μs | 3.140 ms | 1.376 ms | 122.371 μs |
| interpolate! CatmullRom | Float32 256^3 | 268.857 ms | 140.569 ms | 76.248 ms | 47.069 ms | 53.624 ms | 28.340 ms | 13.501 ms | 7.328 ms | — | 14.577 ms | 2.785 ms | 867.350 μs |
| interpolate! CatmullRom | Float32 512^3 | — | — | — | — | 1.815 s | 926.248 ms | 471.745 ms | 267.260 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.330 ms | 707.606 μs | 429.986 μs | 298.117 μs | 626.226 μs | 330.353 μs | 201.532 μs | 134.252 μs | 101.321 μs | 1.724 ms | 1.188 ms | 84.421 μs |
| interpolate! CatmullRom | Float64 128^3 | 13.574 ms | 7.040 ms | 3.450 ms | 1.864 ms | 5.713 ms | 2.877 ms | 1.445 ms | 776.637 μs | 1.411 ms | 2.789 ms | 1.410 ms | 195.203 μs |
| interpolate! CatmullRom | Float64 256^3 | 308.898 ms | 160.669 ms | 90.355 ms | 61.546 ms | 154.507 ms | 71.476 ms | 37.723 ms | 19.711 ms | — | 12.939 ms | 2.854 ms | 1.713 ms |
| interpolate! CatmullRom | Float64 512^3 | — | — | — | — | 2.074 s | 1.061 s | 556.414 ms | 296.880 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.388 ms | 736.185 μs | 452.091 μs | 313.619 μs | 676.297 μs | 359.374 μs | 215.892 μs | 144.661 μs | 166.201 μs | 1.759 ms | 1.283 ms | 112.201 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.639 ms | 37.366 ms | 18.866 ms | 10.513 ms | 42.455 ms | 21.422 ms | 10.746 ms | 5.648 ms | 5.370 ms | 14.027 ms | 3.038 ms | 465.615 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.436 s | 797.249 ms | 506.521 ms | 326.812 ms | 364.130 ms | 174.392 ms | 89.482 ms | 47.681 ms | — | 30.216 ms | 11.603 ms | 4.708 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 5.496 s | 2.855 s | 1.532 s | 901.570 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.891 ms | 4.737 ms | 2.871 ms | 1.919 ms | 5.124 ms | 2.694 ms | 1.624 ms | 1.083 ms | 688.416 μs | 3.166 ms | 1.783 ms | 270.574 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 84.423 ms | 44.133 ms | 21.544 ms | 12.777 ms | 41.617 ms | 20.883 ms | 10.525 ms | 5.541 ms | 8.105 ms | 9.517 ms | 2.980 ms | 841.871 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.917 s | 1.044 s | 656.725 ms | 445.344 ms | 584.434 ms | 284.101 ms | 152.613 ms | 74.127 ms | — | 28.103 ms | 10.932 ms | 10.000 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 6.814 s | 3.566 s | 2.080 s | 1.155 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.136 ms | 4.846 ms | 2.919 ms | 2.001 ms | 5.286 ms | 2.834 ms | 1.672 ms | 1.117 ms | 911.428 μs | 3.595 ms | 2.314 ms | 318.544 μs |
| interpolate! NUFFT | Float32 128^3 | 334.277 ms | 190.430 ms | 136.858 ms | 107.918 ms | 254.596 ms | 132.080 ms | 83.941 ms | 45.631 ms | 12.723 ms | 16.422 ms | 4.893 ms | 1.884 ms |
| interpolate! NUFFT | Float32 256^3 | 3.696 s | 2.083 s | 1.374 s | 1.021 s | 2.981 s | 1.616 s | 940.693 ms | 610.125 ms | — | 72.243 ms | 26.214 ms | 17.610 ms |
| interpolate! NUFFT | Float32 512^3 | — | — | — | — | 24.553 s | 13.330 s | 7.683 s | 4.937 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 17.596 ms | 10.102 ms | 6.982 ms | 5.227 ms | 12.092 ms | 6.569 ms | 3.743 ms | 2.426 ms | 1.847 ms | 4.302 ms | 2.275 ms | 413.776 μs |
| interpolate! NUFFT | Float64 128^3 | 441.632 ms | 269.812 ms | 199.426 ms | 174.008 ms | 221.869 ms | 138.955 ms | 94.695 ms | 64.989 ms | 25.361 ms | 18.237 ms | 8.627 ms | 5.538 ms |
| interpolate! NUFFT | Float64 256^3 | 3.933 s | 2.378 s | 1.723 s | 1.382 s | 2.040 s | 1.248 s | 867.055 ms | 717.217 ms | — | 118.516 ms | 56.632 ms | 47.705 ms |
| interpolate! NUFFT | Float64 512^3 | — | — | — | — | 24.856 s | 14.191 s | 8.687 s | 9.380 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 22.680 ms | 14.315 ms | 10.764 ms | 12.844 ms | 17.907 ms | 9.885 ms | 6.068 ms | 4.102 ms | 3.417 ms | 6.116 ms | 3.003 ms | 930.659 μs |
| interpolate! trilinear | Float32 128^3 | 1.989 ms | 1.020 ms | 524.497 μs | 296.909 μs | 1.305 ms | 689.897 μs | 337.193 μs | 179.602 μs | 255.582 μs | 1.719 ms | 1.094 ms | 64.600 μs |
| interpolate! trilinear | Float32 256^3 | 53.317 ms | 27.939 ms | 15.494 ms | 8.996 ms | 13.998 ms | 7.523 ms | 3.437 ms | 1.871 ms | — | 3.594 ms | 1.280 ms | 251.003 μs |
| interpolate! trilinear | Float32 512^3 | — | — | — | — | 430.979 ms | 218.136 ms | 121.634 ms | 61.471 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 230.008 μs | 123.839 μs | 78.553 μs | 56.457 μs | 149.611 μs | 79.281 μs | 47.590 μs | 33.240 μs | 65.160 μs | 1.448 ms | 957.585 μs | 61.161 μs |
| interpolate! trilinear | Float64 128^3 | 2.515 ms | 1.250 ms | 633.391 μs | 352.008 μs | 1.356 ms | 709.787 μs | 349.534 μs | 189.212 μs | 325.503 μs | 1.772 ms | 1.092 ms | 95.381 μs |
| interpolate! trilinear | Float64 256^3 | 60.532 ms | 33.103 ms | 20.332 ms | 13.578 ms | 33.796 ms | 16.799 ms | 8.218 ms | 4.202 ms | — | 4.014 ms | 1.595 ms | 403.745 μs |
| interpolate! trilinear | Float64 512^3 | — | — | — | — | 442.762 ms | 233.803 ms | 125.512 ms | 63.333 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 242.215 μs | 132.123 μs | 81.993 μs | 58.679 μs | 163.782 μs | 86.521 μs | 50.200 μs | 33.651 μs | 65.930 μs | 1.530 ms | 1.083 ms | 65.070 μs |

## reductions

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.102 ms | 6.883 ms | 8.526 ms | 7.553 ms | 6.963 ms | 4.943 ms | 5.829 ms | 6.063 ms | 2.099 ms | 27.761 ms | 1.656 ms | 302.463 μs |
| co-spectrum vec.vec | Float32 256^3 | 64.148 ms | 47.964 ms | 47.197 ms | 44.996 ms | 55.712 ms | 37.209 ms | 31.618 ms | 29.649 ms | — | 97.666 ms | 3.211 ms | 948.830 μs |
| co-spectrum vec.vec | Float32 512^3 | — | — | — | — | 440.773 ms | 272.325 ms | 189.961 ms | 152.090 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.073 ms | 1.382 ms | 1.379 ms | 1.655 ms | 904.859 μs | 941.690 μs | 1.214 ms | 1.343 ms | 491.824 μs | 17.761 ms | 1.383 ms | 192.883 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.483 ms | 6.754 ms | 6.326 ms | 5.270 ms | 7.257 ms | 5.184 ms | 4.713 ms | 4.477 ms | 2.194 ms | 29.708 ms | 29.468 ms | 374.955 μs |
| co-spectrum vec.vec | Float64 256^3 | 69.508 ms | 49.469 ms | 37.922 ms | 32.666 ms | 58.555 ms | 37.312 ms | 28.203 ms | 22.565 ms | — | 109.563 ms | 66.321 ms | 1.380 ms |
| co-spectrum vec.vec | Float64 512^3 | — | — | — | — | 462.419 ms | 285.279 ms | 178.714 ms | 128.927 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.091 ms | 780.130 μs | 1.076 ms | 1.078 ms | 944.150 μs | 740.978 μs | 886.121 μs | 937.238 μs | 482.135 μs | 16.075 ms | 16.001 ms | 184.602 μs |
| cross-correlation vec.vec | Float32 128^3 | 41.006 ms | 33.640 ms | 34.258 ms | 34.170 ms | 38.354 ms | 29.434 ms | 23.722 ms | 22.109 ms | 5.891 ms | 43.640 ms | 2.622 ms | 660.748 μs |
| cross-correlation vec.vec | Float32 256^3 | 603.733 ms | 447.701 ms | 312.141 ms | 272.731 ms | 802.665 ms | 560.674 ms | 329.799 ms | 260.625 ms | — | 186.915 ms | 10.470 ms | 5.817 ms |
| cross-correlation vec.vec | Float32 512^3 | — | — | — | — | 8.021 s | 5.503 s | 2.976 s | 2.190 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.897 ms | 5.341 ms | 5.453 ms | 5.574 ms | 3.991 ms | 3.771 ms | 3.875 ms | 3.739 ms | 1.025 ms | 20.682 ms | 1.467 ms | 263.693 μs |
| cross-correlation vec.vec | Float64 128^3 | 72.908 ms | 62.435 ms | 52.125 ms | 47.305 ms | 70.772 ms | 51.930 ms | 40.521 ms | 33.714 ms | 9.144 ms | 52.055 ms | 51.351 ms | 2.077 ms |
| cross-correlation vec.vec | Float64 256^3 | 733.386 ms | 533.079 ms | 388.133 ms | 351.464 ms | 620.211 ms | 436.611 ms | 290.447 ms | 265.683 ms | — | 217.471 ms | 137.382 ms | 16.292 ms |
| cross-correlation vec.vec | Float64 512^3 | — | — | — | — | 4.786 s | 3.318 s | 2.160 s | 1.858 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 6.102 ms | 5.839 ms | 5.674 ms | 5.496 ms | 4.742 ms | 3.800 ms | 3.548 ms | 3.415 ms | 1.557 ms | 20.881 ms | 23.884 ms | 309.303 μs |
| inner spectral | Float32 128^3 | 2.693 ms | 1.825 ms | 1.415 ms | 1.242 ms | 573.506 μs | 529.326 μs | 527.676 μs | 529.245 μs | 669.926 μs | 2.049 ms | 1.209 ms | 254.113 μs |
| inner spectral | Float32 256^3 | 22.068 ms | 17.305 ms | 14.959 ms | 14.806 ms | 7.849 ms | 8.161 ms | 8.011 ms | 7.666 ms | — | 3.999 ms | 1.750 ms | 739.028 μs |
| inner spectral | Float32 512^3 | — | — | — | — | 78.468 ms | 79.565 ms | 79.283 ms | 78.713 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 311.447 μs | 198.822 μs | 139.780 μs | 111.743 μs | 88.700 μs | 97.261 μs | 88.091 μs | 87.361 μs | 275.972 μs | 1.780 ms | 1.135 ms | 193.153 μs |
| inner spectral | Float64 128^3 | 4.669 ms | 3.596 ms | 3.238 ms | 2.873 ms | 601.866 μs | 619.016 μs | 628.597 μs | 630.346 μs | 811.337 μs | 2.410 ms | 1.363 ms | 328.904 μs |
| inner spectral | Float64 256^3 | 36.055 ms | 30.098 ms | 27.776 ms | 27.041 ms | 15.916 ms | 16.087 ms | 16.069 ms | 15.835 ms | — | 7.953 ms | 2.789 ms | 1.219 ms |
| inner spectral | Float64 512^3 | — | — | — | — | 129.106 ms | 128.999 ms | 131.471 ms | 128.553 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 320.929 μs | 209.181 μs | 150.847 μs | 127.356 μs | 68.660 μs | 67.941 μs | 67.421 μs | 68.211 μs | 293.003 μs | 1.765 ms | 1.138 ms | 207.912 μs |
| inner vec.vec | Float32 128^3 | 1.299 ms | 1.004 ms | 809.900 μs | 714.646 μs | 310.603 μs | 311.603 μs | 309.114 μs | 310.483 μs | 308.353 μs | 1.623 ms | 794.094 μs | 113.121 μs |
| inner vec.vec | Float32 256^3 | 14.078 ms | 12.444 ms | 11.394 ms | 10.665 ms | 5.982 ms | 5.956 ms | 6.056 ms | 5.893 ms | — | 3.382 ms | 1.298 ms | 566.146 μs |
| inner vec.vec | Float32 512^3 | — | — | — | — | 57.471 ms | 56.849 ms | 56.755 ms | 56.696 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 71.008 μs | 38.481 μs | 20.591 μs | 15.112 μs | 38.420 μs | 38.340 μs | 38.301 μs | 38.460 μs | 98.731 μs | 1.278 ms | 774.243 μs | 78.381 μs |
| inner vec.vec | Float64 128^3 | 3.229 ms | 2.545 ms | 2.297 ms | 2.130 ms | 215.102 μs | 212.982 μs | 230.532 μs | 229.602 μs | 552.615 μs | 1.860 ms | 998.015 μs | 227.613 μs |
| inner vec.vec | Float64 256^3 | 27.337 ms | 24.795 ms | 23.214 ms | 22.210 ms | 13.001 ms | 12.999 ms | 13.012 ms | 13.030 ms | — | 5.634 ms | 2.038 ms | 1.074 ms |
| inner vec.vec | Float64 512^3 | — | — | — | — | 111.905 ms | 110.511 ms | 110.374 ms | 110.391 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 139.198 μs | 74.424 μs | 40.368 μs | 25.052 μs | 10.300 μs | 10.490 μs | 10.520 μs | 10.370 μs | 162.792 μs | 1.434 ms | 777.319 μs | 110.331 μs |
| integral scalar | Float32 128^3 | 108.935 μs | 61.065 μs | 30.329 μs | 19.319 μs | 59.491 μs | 59.571 μs | 60.341 μs | 60.610 μs | 228.932 μs | 1.318 ms | 1.144 ms | 103.911 μs |
| integral scalar | Float32 256^3 | 2.062 ms | 1.546 ms | 1.288 ms | 1.176 ms | 559.905 μs | 573.756 μs | 543.166 μs | 540.015 μs | — | 9.002 ms | 2.302 ms | 251.973 μs |
| integral scalar | Float32 512^3 | — | — | — | — | 10.690 ms | 11.047 ms | 10.218 ms | 10.492 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 10.805 μs | 6.550 μs | 5.359 μs | 6.136 μs | 6.794 μs | 6.486 μs | 6.848 μs | 6.684 μs | 95.301 μs | 1.534 ms | 899.409 μs | 81.891 μs |
| integral scalar | Float64 128^3 | 259.555 μs | 132.832 μs | 66.498 μs | 38.281 μs | 120.512 μs | 120.671 μs | 118.091 μs | 118.891 μs | 221.812 μs | 2.553 ms | 1.192 ms | 104.511 μs |
| integral scalar | Float64 256^3 | 5.300 ms | 3.921 ms | 3.222 ms | 3.017 ms | 2.017 ms | 1.944 ms | 1.950 ms | 1.990 ms | — | 10.817 ms | 2.694 ms | 260.473 μs |
| integral scalar | Float64 512^3 | — | — | — | — | 19.719 ms | 18.984 ms | 19.761 ms | 19.951 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.915 μs | 12.813 μs | 7.820 μs | 7.365 μs | 14.740 μs | 15.220 μs | 15.380 μs | 15.780 μs | 95.391 μs | 1.583 ms | 853.383 μs | 79.731 μs |
| integral spectral vec | Float32 128^3 | 82.756 ns | 67.028 ns | 67.401 ns | 67.096 ns | 70.297 ns | 73.526 ns | 69.817 ns | 69.026 ns | — | — | 847.189 μs | 55.981 μs |
| integral spectral vec | Float32 256^3 | 83.001 ns | 67.412 ns | 67.345 ns | 67.259 ns | 70.575 ns | 74.079 ns | 70.278 ns | 69.246 ns | — | — | 812.731 μs | 50.261 μs |
| integral spectral vec | Float32 512^3 | — | — | — | — | 71.168 ns | 76.688 ns | 72.982 ns | 68.942 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 84.414 ns | 66.859 ns | 67.099 ns | 66.889 ns | 70.565 ns | 76.156 ns | 69.550 ns | 71.214 ns | — | — | 833.215 μs | 53.991 μs |
| integral spectral vec | Float64 128^3 | 68.411 ns | 69.034 ns | 68.132 ns | 68.141 ns | 74.697 ns | 73.892 ns | 75.325 ns | 74.779 ns | — | — | 832.384 μs | 49.151 μs |
| integral spectral vec | Float64 256^3 | 68.706 ns | 69.471 ns | 69.518 ns | 69.298 ns | 76.562 ns | 74.703 ns | 77.031 ns | 76.507 ns | — | — | 808.714 μs | 52.850 μs |
| integral spectral vec | Float64 512^3 | — | — | — | — | 76.606 ns | 78.892 ns | 80.771 ns | 80.423 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 69.871 ns | 69.056 ns | 67.752 ns | 73.262 ns | 76.291 ns | 76.911 ns | 75.273 ns | 77.413 ns | — | — | 842.906 μs | 59.781 μs |
| l2norm vec | Float32 128^3 | 610.109 μs | 366.752 μs | 170.329 μs | 95.231 μs | 166.301 μs | 166.672 μs | 166.042 μs | 167.031 μs | 196.632 μs | 1.582 ms | 854.011 μs | 96.431 μs |
| l2norm vec | Float32 256^3 | 8.414 ms | 5.982 ms | 5.392 ms | 4.988 ms | 2.802 ms | 2.635 ms | 2.448 ms | 2.410 ms | — | 3.219 ms | 1.301 ms | 344.154 μs |
| l2norm vec | Float32 512^3 | — | — | — | — | 26.369 ms | 28.098 ms | 28.146 ms | 26.477 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 49.849 μs | 27.581 μs | 15.476 μs | 13.562 μs | 21.941 μs | 22.590 μs | 22.060 μs | 19.080 μs | 85.641 μs | 1.361 ms | 756.839 μs | 83.641 μs |
| l2norm vec | Float64 128^3 | 1.784 ms | 1.082 ms | 820.889 μs | 700.280 μs | 63.121 μs | 63.020 μs | 63.381 μs | 62.941 μs | 344.333 μs | 1.876 ms | 978.559 μs | 151.392 μs |
| l2norm vec | Float64 256^3 | 16.021 ms | 12.268 ms | 11.079 ms | 10.408 ms | 5.572 ms | 5.488 ms | 5.557 ms | 5.470 ms | — | 5.670 ms | 1.957 ms | 592.297 μs |
| l2norm vec | Float64 512^3 | — | — | — | — | 54.771 ms | 54.727 ms | 54.749 ms | 54.726 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 94.777 μs | 51.183 μs | 26.945 μs | 18.906 μs | 4.073 μs | 4.037 μs | 3.853 μs | 4.166 μs | 134.871 μs | 1.402 ms | 773.034 μs | 116.891 μs |
| lpnorm vec Inf | Float32 128^3 | 1.336 ms | 1.304 ms | 1.158 ms | 1.023 ms | 460.005 μs | 375.843 μs | 336.824 μs | 313.462 μs | 592.145 μs | 3.080 ms | 1.319 ms | 141.592 μs |
| lpnorm vec Inf | Float32 256^3 | 21.907 ms | 15.102 ms | 11.774 ms | 10.716 ms | 18.521 ms | 10.809 ms | 8.185 ms | 8.526 ms | — | 13.216 ms | 3.421 ms | 582.917 μs |
| lpnorm vec Inf | Float32 512^3 | — | — | — | — | 133.478 ms | 86.939 ms | 75.743 ms | 73.265 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 97.792 μs | 84.768 μs | 70.909 μs | 77.481 μs | 61.141 μs | 49.330 μs | 41.811 μs | 42.150 μs | 155.751 μs | 1.641 ms | 964.230 μs | 114.502 μs |
| lpnorm vec Inf | Float64 128^3 | 3.088 ms | 3.081 ms | 2.654 ms | 2.510 ms | 1.134 ms | 1.111 ms | 998.952 μs | 917.658 μs | 660.476 μs | 3.883 ms | 1.668 ms | 235.313 μs |
| lpnorm vec Inf | Float64 256^3 | 45.010 ms | 29.712 ms | 23.393 ms | 21.488 ms | 32.658 ms | 21.320 ms | 15.537 ms | 17.128 ms | — | 14.730 ms | 5.382 ms | 957.511 μs |
| lpnorm vec Inf | Float64 512^3 | — | — | — | — | 247.062 ms | 161.625 ms | 140.362 ms | 138.177 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 235.890 μs | 177.791 μs | 151.144 μs | 133.722 μs | 111.411 μs | 93.091 μs | 76.691 μs | 72.640 μs | 166.092 μs | 1.711 ms | 1.005 ms | 112.441 μs |
| maximum scalar | Float32 128^3 | 337.996 μs | 176.232 μs | 90.830 μs | 51.478 μs | 233.623 μs | 232.952 μs | 230.723 μs | 231.102 μs | 223.322 μs | 2.331 ms | 1.146 ms | 95.251 μs |
| maximum scalar | Float32 256^3 | 2.881 ms | 1.744 ms | 1.442 ms | 1.208 ms | 1.848 ms | 1.890 ms | 1.897 ms | 1.843 ms | — | 9.121 ms | 2.319 ms | 249.532 μs |
| maximum scalar | Float32 512^3 | — | — | — | — | 23.848 ms | 23.635 ms | 28.431 ms | 26.625 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 43.044 μs | 24.572 μs | 14.041 μs | 11.695 μs | 28.880 μs | 28.890 μs | 28.860 μs | 28.930 μs | 101.731 μs | 1.564 ms | 922.422 μs | 87.732 μs |
| maximum scalar | Float64 128^3 | 560.040 μs | 287.354 μs | 145.073 μs | 78.345 μs | 435.094 μs | 435.835 μs | 438.945 μs | 441.424 μs | 244.072 μs | 2.772 ms | 1.301 ms | 104.391 μs |
| maximum scalar | Float64 256^3 | 6.896 ms | 4.246 ms | 3.355 ms | 3.072 ms | 4.123 ms | 4.113 ms | 4.841 ms | 3.964 ms | — | 12.659 ms | 3.329 ms | 293.543 μs |
| maximum scalar | Float64 512^3 | — | — | — | — | 45.073 ms | 43.204 ms | 44.383 ms | 43.078 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 66.566 μs | 36.620 μs | 20.534 μs | 13.743 μs | 54.721 μs | 54.891 μs | 54.831 μs | 54.821 μs | 99.451 μs | 1.634 ms | 947.833 μs | 102.931 μs |
| maximum(norm) vec | Float32 128^3 | 1.798 ms | 922.690 μs | 470.264 μs | 245.817 μs | 774.138 μs | 775.448 μs | 772.618 μs | 772.578 μs | — | — | 1.234 ms | 116.401 μs |
| maximum(norm) vec | Float32 256^3 | 14.744 ms | 8.084 ms | 5.701 ms | 5.110 ms | 8.498 ms | 8.109 ms | 8.022 ms | 8.333 ms | — | — | 2.782 ms | 358.784 μs |
| maximum(norm) vec | Float32 512^3 | — | — | — | — | 63.883 ms | 64.994 ms | 65.666 ms | 60.116 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 224.979 μs | 116.123 μs | 61.392 μs | 35.198 μs | 96.461 μs | 97.171 μs | 96.501 μs | 96.671 μs | — | — | 920.168 μs | 93.671 μs |
| maximum(norm) vec | Float64 128^3 | 5.215 ms | 2.677 ms | 1.379 ms | 824.319 μs | 1.585 ms | 1.586 ms | 1.586 ms | 1.583 ms | — | — | 1.571 ms | 228.253 μs |
| maximum(norm) vec | Float64 256^3 | 42.152 ms | 21.453 ms | 12.819 ms | 10.721 ms | 15.693 ms | 14.204 ms | 14.062 ms | 13.814 ms | — | — | 4.860 ms | 1.049 ms |
| maximum(norm) vec | Float64 512^3 | — | — | — | — | 121.105 ms | 116.761 ms | 120.970 ms | 115.756 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 651.845 μs | 329.878 μs | 167.231 μs | 89.962 μs | 197.172 μs | 197.152 μs | 197.392 μs | 197.792 μs | — | — | 979.833 μs | 110.241 μs |
| mean spectral vec | Float32 128^3 | 70.164 ns | 76.856 ns | 70.037 ns | 69.777 ns | 73.560 ns | 71.898 ns | 74.205 ns | 73.136 ns | — | — | 820.577 μs | 55.850 μs |
| mean spectral vec | Float32 256^3 | 71.200 ns | 71.128 ns | 70.059 ns | 70.376 ns | 74.052 ns | 72.288 ns | 74.831 ns | 74.040 ns | — | — | 812.941 μs | 48.701 μs |
| mean spectral vec | Float32 512^3 | — | — | — | — | 74.822 ns | 74.616 ns | 77.133 ns | 76.656 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 77.294 ns | 70.502 ns | 69.764 ns | 69.437 ns | 74.518 ns | 74.779 ns | 73.763 ns | 76.087 ns | — | — | 833.055 μs | 47.661 μs |
| mean spectral vec | Float64 128^3 | 70.843 ns | 71.788 ns | 71.017 ns | 70.951 ns | 77.305 ns | 80.135 ns | 78.178 ns | 78.245 ns | — | — | 814.812 μs | 50.101 μs |
| mean spectral vec | Float64 256^3 | 71.674 ns | 72.882 ns | 72.221 ns | 73.114 ns | 78.296 ns | 80.934 ns | 79.207 ns | 79.102 ns | — | — | 848.819 μs | 52.330 μs |
| mean spectral vec | Float64 512^3 | — | — | — | — | 79.310 ns | 84.487 ns | 82.957 ns | 83.261 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 71.962 ns | 71.652 ns | 70.907 ns | 71.366 ns | 78.844 ns | 82.656 ns | 78.312 ns | 81.397 ns | — | — | 830.467 μs | 61.530 μs |
| mean vector | Float32 128^3 | 526.294 μs | 330.193 μs | 183.201 μs | 110.555 μs | 197.522 μs | 183.591 μs | 196.522 μs | 199.162 μs | 633.756 μs | 4.808 ms | 1.887 ms | 220.302 μs |
| mean vector | Float32 256^3 | 7.900 ms | 5.871 ms | 5.298 ms | 4.972 ms | 3.442 ms | 3.295 ms | 3.318 ms | 3.120 ms | — | 16.657 ms | 5.531 ms | 1.256 ms |
| mean vector | Float32 512^3 | — | — | — | — | 32.767 ms | 34.338 ms | 34.414 ms | 34.655 ms | — | — | — | — |
| mean vector | Float32 64^3 | 50.583 μs | 32.153 μs | 24.798 μs | 33.475 μs | 25.151 μs | 25.560 μs | 26.340 μs | 24.580 μs | 162.362 μs | 1.846 ms | 1.302 ms | 95.132 μs |
| mean vector | Float64 128^3 | 1.763 ms | 1.020 ms | 817.724 μs | 732.363 μs | 399.504 μs | 398.394 μs | 398.024 μs | 381.823 μs | 657.486 μs | 5.195 ms | 1.836 ms | 250.023 μs |
| mean vector | Float64 256^3 | 15.192 ms | 12.381 ms | 11.109 ms | 10.825 ms | 8.345 ms | 8.951 ms | 7.861 ms | 7.927 ms | — | 17.799 ms | 6.369 ms | 1.431 ms |
| mean vector | Float64 512^3 | — | — | — | — | 59.505 ms | 54.611 ms | 62.191 ms | 54.804 ms | — | — | — | — |
| mean vector | Float64 64^3 | 90.004 μs | 58.542 μs | 38.211 μs | 39.539 μs | 46.430 μs | 45.880 μs | 45.731 μs | 46.001 μs | 156.311 μs | 1.913 ms | 1.281 ms | 104.491 μs |
| mean(det) tensor | Float32 128^3 | 2.286 ms | 1.848 ms | 1.606 ms | 1.464 ms | 775.598 μs | 746.647 μs | 780.828 μs | 760.517 μs | — | — | 1.280 ms | 216.973 μs |
| mean(det) tensor | Float32 256^3 | 23.045 ms | 20.537 ms | 18.316 ms | 17.088 ms | 16.008 ms | 16.121 ms | 15.834 ms | 16.114 ms | — | — | 3.413 ms | 827.249 μs |
| mean(det) tensor | Float32 512^3 | — | — | — | — | 116.056 ms | 103.252 ms | 106.714 ms | 107.227 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 102.513 μs | 55.732 μs | 29.880 μs | 19.796 μs | 67.380 μs | 67.301 μs | 68.231 μs | 68.360 μs | — | — | 937.045 μs | 96.492 μs |
| mean(det) tensor | Float64 128^3 | 5.035 ms | 4.499 ms | 3.871 ms | 3.629 ms | 2.528 ms | 2.574 ms | 2.515 ms | 2.403 ms | — | — | 1.491 ms | 278.443 μs |
| mean(det) tensor | Float64 256^3 | 47.274 ms | 42.027 ms | 37.977 ms | 35.443 ms | 30.276 ms | 30.852 ms | 30.873 ms | 29.208 ms | — | — | 4.560 ms | 1.529 ms |
| mean(det) tensor | Float64 512^3 | — | — | — | — | 202.383 ms | 199.329 ms | 225.172 ms | 221.797 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 230.761 μs | 127.967 μs | 74.678 μs | 40.886 μs | 129.971 μs | 131.021 μs | 131.931 μs | 129.592 μs | — | — | 972.637 μs | 110.861 μs |
| mean(norm) vec | Float32 128^3 | 1.549 ms | 798.422 μs | 409.598 μs | 212.931 μs | 607.756 μs | 608.697 μs | 606.247 μs | 597.655 μs | — | — | 538.869 μs | 118.782 μs |
| mean(norm) vec | Float32 256^3 | 12.750 ms | 7.152 ms | 5.592 ms | 5.155 ms | 7.570 ms | 7.169 ms | 7.120 ms | 7.426 ms | — | — | 2.833 ms | 372.454 μs |
| mean(norm) vec | Float32 512^3 | — | — | — | — | 58.272 ms | 58.321 ms | 58.692 ms | 53.962 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 193.060 μs | 99.869 μs | 53.256 μs | 30.898 μs | 75.931 μs | 75.880 μs | 75.801 μs | 75.881 μs | — | — | 921.051 μs | 82.152 μs |
| mean(norm) vec | Float64 128^3 | 5.145 ms | 2.643 ms | 1.363 ms | 818.392 μs | 1.444 ms | 1.443 ms | 1.443 ms | 1.429 ms | — | — | 1.332 ms | 214.393 μs |
| mean(norm) vec | Float64 256^3 | 41.521 ms | 21.187 ms | 12.631 ms | 10.998 ms | 14.160 ms | 13.279 ms | 13.540 ms | 13.275 ms | — | — | 4.325 ms | 937.881 μs |
| mean(norm) vec | Float64 512^3 | — | — | — | — | 108.676 ms | 105.941 ms | 112.332 ms | 104.864 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 632.065 μs | 324.426 μs | 165.163 μs | 88.919 μs | 179.902 μs | 180.292 μs | 179.252 μs | 182.882 μs | — | — | 957.695 μs | 97.391 μs |
| mean(tr) tensor | Float32 128^3 | 417.927 μs | 251.765 μs | 140.475 μs | 69.092 μs | 208.492 μs | 200.982 μs | 195.122 μs | 186.782 μs | — | — | 1.200 ms | 118.752 μs |
| mean(tr) tensor | Float32 256^3 | 6.447 ms | 5.977 ms | 5.354 ms | 4.935 ms | 3.285 ms | 3.268 ms | 3.202 ms | 3.266 ms | — | — | 2.699 ms | 347.843 μs |
| mean(tr) tensor | Float32 512^3 | — | — | — | — | 37.432 ms | 32.751 ms | 33.346 ms | 33.338 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 34.292 μs | 18.570 μs | 12.563 μs | 11.085 μs | 25.640 μs | 24.480 μs | 25.470 μs | 24.870 μs | — | — | 910.276 μs | 86.181 μs |
| mean(tr) tensor | Float64 128^3 | 1.329 ms | 972.602 μs | 803.650 μs | 696.706 μs | 401.624 μs | 405.934 μs | 357.554 μs | 354.103 μs | — | — | 1.170 ms | 158.182 μs |
| mean(tr) tensor | Float64 256^3 | 13.458 ms | 12.492 ms | 11.350 ms | 10.695 ms | 7.067 ms | 7.204 ms | 7.086 ms | 6.751 ms | — | — | 3.285 ms | 586.687 μs |
| mean(tr) tensor | Float64 512^3 | — | — | — | — | 65.776 ms | 65.974 ms | 75.282 ms | 76.141 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 67.919 μs | 37.905 μs | 19.640 μs | 15.174 μs | 43.210 μs | 43.141 μs | 42.650 μs | 43.141 μs | — | — | 921.594 μs | 98.281 μs |
| radial_correlation vec | Float32 128^3 | 38.648 ms | 34.170 ms | 33.614 ms | 33.207 ms | 35.831 ms | 26.677 ms | 23.279 ms | 22.107 ms | 5.783 ms | 42.875 ms | 2.515 ms | 764.119 μs |
| radial_correlation vec | Float32 256^3 | 590.485 ms | 433.725 ms | 310.182 ms | 273.181 ms | 785.305 ms | 541.151 ms | 324.192 ms | 260.480 ms | — | 185.439 ms | 10.286 ms | 5.598 ms |
| radial_correlation vec | Float32 512^3 | — | — | — | — | 7.887 s | 5.300 s | 2.924 s | 2.168 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.605 ms | 5.287 ms | 5.423 ms | 5.600 ms | 3.657 ms | 3.498 ms | 3.666 ms | 3.585 ms | 1.010 ms | 19.917 ms | 1.555 ms | 265.364 μs |
| radial_correlation vec | Float64 128^3 | 71.083 ms | 59.068 ms | 50.705 ms | 47.029 ms | 68.417 ms | 52.441 ms | 37.958 ms | 32.627 ms | 9.025 ms | 52.060 ms | 47.229 ms | 2.011 ms |
| radial_correlation vec | Float64 256^3 | 718.316 ms | 518.765 ms | 385.104 ms | 350.915 ms | 584.739 ms | 418.431 ms | 282.432 ms | 251.434 ms | — | 219.151 ms | 138.359 ms | 14.793 ms |
| radial_correlation vec | Float64 512^3 | — | — | — | — | 4.622 s | 3.179 s | 2.060 s | 1.779 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.828 ms | 5.649 ms | 5.547 ms | 5.338 ms | 4.341 ms | 3.649 ms | 3.473 ms | 3.419 ms | 1.413 ms | 21.203 ms | 23.553 ms | 332.923 μs |
| radial_spectrum vec | Float32 128^3 | 7.539 ms | 5.696 ms | 7.580 ms | 7.878 ms | 6.323 ms | 4.770 ms | 5.777 ms | 6.003 ms | 1.415 ms | 27.166 ms | 1.792 ms | 301.463 μs |
| radial_spectrum vec | Float32 256^3 | 59.829 ms | 45.815 ms | 45.991 ms | 42.808 ms | 50.072 ms | 33.099 ms | 31.191 ms | 29.876 ms | — | 96.772 ms | 3.246 ms | 929.290 μs |
| radial_spectrum vec | Float32 512^3 | — | — | — | — | 399.113 ms | 236.199 ms | 179.391 ms | 153.977 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 996.016 μs | 1.414 ms | 1.612 ms | 1.518 ms | 821.999 μs | 917.169 μs | 1.165 ms | 1.314 ms | 344.443 μs | 16.995 ms | 1.190 ms | 168.323 μs |
| radial_spectrum vec | Float64 128^3 | 7.557 ms | 5.778 ms | 5.802 ms | 5.611 ms | 6.538 ms | 4.623 ms | 4.379 ms | 4.424 ms | 1.515 ms | 29.791 ms | 28.854 ms | 369.315 μs |
| radial_spectrum vec | Float64 256^3 | 60.377 ms | 40.900 ms | 34.201 ms | 32.487 ms | 51.923 ms | 32.034 ms | 25.355 ms | 22.623 ms | — | 110.504 ms | 67.077 ms | 1.375 ms |
| radial_spectrum vec | Float64 512^3 | — | — | — | — | 414.615 ms | 252.253 ms | 164.160 ms | 123.648 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 979.453 μs | 748.844 μs | 1.106 ms | 1.157 ms | 846.368 μs | 683.987 μs | 828.479 μs | 956.318 μs | 380.613 μs | 16.740 ms | 15.470 ms | 180.582 μs |
| weighted_inner vec | Float32 128^3 | 12.309 ms | 12.305 ms | 12.358 ms | 12.374 ms | 10.293 ms | 10.312 ms | 10.352 ms | 10.292 ms | — | — | 1.428 ms | 155.612 μs |
| weighted_inner vec | Float32 256^3 | 97.283 ms | 96.797 ms | 96.756 ms | 97.673 ms | 81.352 ms | 80.999 ms | 82.824 ms | 80.931 ms | — | — | 4.280 ms | 629.417 μs |
| weighted_inner vec | Float32 512^3 | — | — | — | — | 641.427 ms | 645.749 ms | 645.721 ms | 645.320 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.622 ms | 1.591 ms | 1.599 ms | 1.596 ms | 1.285 ms | 1.282 ms | 1.285 ms | 1.340 ms | — | — | 1.020 ms | 93.402 μs |
| weighted_inner vec | Float64 128^3 | 13.324 ms | 13.282 ms | 13.288 ms | 13.299 ms | 10.894 ms | 10.902 ms | 10.901 ms | 10.895 ms | — | — | 1.679 ms | 173.772 μs |
| weighted_inner vec | Float64 256^3 | 106.104 ms | 106.032 ms | 105.590 ms | 105.786 ms | 85.807 ms | 85.849 ms | 85.834 ms | 85.861 ms | — | — | 5.232 ms | 1.063 ms |
| weighted_inner vec | Float64 512^3 | — | — | — | — | 679.598 ms | 682.375 ms | 680.618 ms | 680.184 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.715 ms | 1.676 ms | 1.678 ms | 1.680 ms | 1.357 ms | 1.442 ms | 1.411 ms | 1.354 ms | — | — | 1.040 ms | 118.101 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.338 ms | 12.368 ms | 12.411 ms | 12.474 ms | 10.304 ms | 10.368 ms | 10.365 ms | 10.299 ms | — | — | 1.362 ms | 168.642 μs |
| weighted_inner vec.vec | Float32 256^3 | 97.938 ms | 97.348 ms | 97.491 ms | 97.991 ms | 81.031 ms | 81.600 ms | 83.731 ms | 81.502 ms | — | — | 4.195 ms | 833.779 μs |
| weighted_inner vec.vec | Float32 512^3 | — | — | — | — | 643.935 ms | 647.162 ms | 643.982 ms | 642.973 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.624 ms | 1.591 ms | 1.597 ms | 1.597 ms | 1.302 ms | 1.284 ms | 1.307 ms | 1.343 ms | — | — | 1.001 ms | 98.001 μs |
| weighted_inner vec.vec | Float64 128^3 | 13.623 ms | 13.545 ms | 13.523 ms | 13.499 ms | 10.921 ms | 10.941 ms | 10.948 ms | 10.931 ms | — | — | 1.584 ms | 269.913 μs |
| weighted_inner vec.vec | Float64 256^3 | 108.214 ms | 108.140 ms | 108.030 ms | 108.282 ms | 85.985 ms | 86.085 ms | 86.256 ms | 86.074 ms | — | — | 5.332 ms | 1.542 ms |
| weighted_inner vec.vec | Float64 512^3 | — | — | — | — | 682.569 ms | 683.018 ms | 778.541 ms | 774.587 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.720 ms | 1.682 ms | 1.688 ms | 1.684 ms | 1.374 ms | 1.458 ms | 1.422 ms | 1.361 ms | — | — | 985.284 μs | 123.831 μs |

