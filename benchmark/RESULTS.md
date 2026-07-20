# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-07-20 at commit `0a3d96b` on Julia 1.12.6, assembled on host `Aiporetne` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`). **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh` plus the per-card / per-CPU archive in `benchmark/results/` (PERFORMANCE.md §6). ~10% jitter.

## fft

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 5.185 ms | 3.332 ms | 2.425 ms | 2.386 ms | 4.495 ms | 2.385 ms | 1.303 ms | 769.998 μs | 788.067 μs | 2.421 ms | 435.844 μs | 211.314 μs |
| to_physical scalar | Float32 256^3 | 120.456 ms | 75.085 ms | 39.701 ms | 37.317 ms | 183.356 ms | 99.965 ms | 57.300 ms | 36.155 ms | — | 7.945 ms | 1.492 ms | 1.138 ms |
| to_physical scalar | Float32 64^3 | 404.712 μs | 256.238 μs | 172.228 μs | 141.909 μs | 319.413 μs | 177.131 μs | 102.111 μs | 70.261 μs | 124.402 μs | 1.497 ms | 335.253 μs | 123.760 μs |
| to_physical scalar | Float64 128^3 | 8.342 ms | 5.868 ms | 5.057 ms | 4.609 ms | 10.150 ms | 5.509 ms | 3.067 ms | 1.796 ms | 1.905 ms | 3.750 ms | 904.753 μs | 546.301 μs |
| to_physical scalar | Float64 256^3 | 154.523 ms | 104.915 ms | 86.850 ms | 81.789 ms | 109.718 ms | 73.373 ms | 53.595 ms | 46.282 ms | — | 14.463 ms | 5.261 ms | 3.878 ms |
| to_physical scalar | Float64 64^3 | 699.028 μs | 443.724 μs | 318.737 μs | 267.959 μs | 535.096 μs | 290.772 μs | 165.272 μs | 113.781 μs | 331.873 μs | 1.784 ms | 392.529 μs | 164.821 μs |
| to_physical vector | Float32 128^3 | 15.516 ms | 11.976 ms | 8.329 ms | 8.304 ms | 14.504 ms | 10.444 ms | 5.206 ms | 3.821 ms | 2.507 ms | 4.595 ms | 826.947 μs | 354.996 μs |
| to_physical vector | Float32 256^3 | 376.172 ms | 273.666 ms | 172.548 ms | 146.567 ms | 586.905 ms | 407.216 ms | 222.861 ms | 160.686 ms | — | 14.844 ms | 5.000 ms | 3.540 ms |
| to_physical vector | Float32 64^3 | 1.327 ms | 997.886 μs | 541.102 μs | 501.331 μs | 1.017 ms | 682.297 μs | 317.024 μs | 220.802 μs | 380.054 μs | 1.776 ms | 359.155 μs | 140.191 μs |
| to_physical vector | Float64 128^3 | 38.026 ms | 31.968 ms | 20.850 ms | 19.459 ms | 38.027 ms | 33.962 ms | 21.141 ms | 15.590 ms | 5.630 ms | 8.090 ms | 2.173 ms | 1.504 ms |
| to_physical vector | Float64 256^3 | 465.868 ms | 359.990 ms | 258.848 ms | 247.224 ms | 350.650 ms | 269.860 ms | 174.293 ms | 154.981 ms | — | 22.812 ms | 13.079 ms | 11.633 ms |
| to_physical vector | Float64 64^3 | 2.791 ms | 2.220 ms | 1.596 ms | 1.213 ms | 1.657 ms | 1.116 ms | 597.267 μs | 416.535 μs | 811.437 μs | 2.301 ms | 618.297 μs | 270.292 μs |
| to_spectral scalar | Float32 128^3 | 4.656 ms | 2.812 ms | 1.691 ms | 1.605 ms | 4.378 ms | 2.282 ms | 1.224 ms | 686.436 μs | 488.254 μs | 2.072 ms | 358.889 μs | 178.183 μs |
| to_spectral scalar | Float32 256^3 | 118.430 ms | 71.360 ms | 36.322 ms | 26.415 ms | 185.606 ms | 98.702 ms | 56.351 ms | 34.797 ms | — | 5.009 ms | 991.167 μs | 782.389 μs |
| to_spectral scalar | Float32 64^3 | 383.004 μs | 218.234 μs | 132.117 μs | 114.514 μs | 303.374 μs | 165.992 μs | 90.931 μs | 59.141 μs | 89.181 μs | 1.538 ms | 355.056 μs | 133.631 μs |
| to_spectral scalar | Float64 128^3 | 7.445 ms | 5.217 ms | 4.181 ms | 3.436 ms | 9.971 ms | 5.411 ms | 2.985 ms | 1.755 ms | 1.501 ms | 3.125 ms | 826.771 μs | 488.550 μs |
| to_spectral scalar | Float64 256^3 | 173.710 ms | 109.655 ms | 80.023 ms | 68.113 ms | 205.510 ms | 116.633 ms | 70.920 ms | 52.515 ms | — | 12.871 ms | 4.227 ms | 3.154 ms |
| to_spectral scalar | Float64 64^3 | 697.766 μs | 371.362 μs | 245.627 μs | 177.574 μs | 507.796 μs | 270.123 μs | 152.822 μs | 95.641 μs | 265.683 μs | 1.745 ms | 436.005 μs | 172.622 μs |
| to_spectral vector | Float32 128^3 | 14.196 ms | 10.079 ms | 6.842 ms | 6.110 ms | 14.934 ms | 10.448 ms | 4.849 ms | 3.668 ms | 1.355 ms | 3.183 ms | 473.980 μs | 248.174 μs |
| to_spectral vector | Float32 256^3 | 359.274 ms | 260.710 ms | 154.655 ms | 127.358 ms | 577.572 ms | 396.628 ms | 212.748 ms | 150.959 ms | — | 11.819 ms | 3.032 ms | 2.286 ms |
| to_spectral vector | Float32 64^3 | 1.232 ms | 935.164 μs | 451.378 μs | 480.330 μs | 980.321 μs | 656.387 μs | 287.083 μs | 181.732 μs | 230.522 μs | 1.566 ms | 311.426 μs | 128.561 μs |
| to_spectral vector | Float64 128^3 | 34.978 ms | 30.297 ms | 19.984 ms | 18.093 ms | 39.836 ms | 35.476 ms | 20.725 ms | 11.176 ms | 4.144 ms | 6.538 ms | 1.592 ms | 1.216 ms |
| to_spectral vector | Float64 256^3 | 519.471 ms | 391.649 ms | 249.990 ms | 225.111 ms | 624.625 ms | 448.682 ms | 252.527 ms | 197.635 ms | — | 20.041 ms | 11.392 ms | 9.255 ms |
| to_spectral vector | Float64 64^3 | 2.408 ms | 1.918 ms | 1.124 ms | 998.238 μs | 1.541 ms | 1.074 ms | 503.276 μs | 347.833 μs | 596.836 μs | 2.151 ms | 540.584 μs | 249.811 μs |

## algebra

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 432.952 μs | 3.604 ms | 1.846 ms | 949.549 μs | 161.872 μs | 2.922 ms | 1.469 ms | 737.287 μs | 351.303 μs | 1.943 ms | 397.824 μs | 163.712 μs |
| add! scalar | Float32 256^3 | 8.609 ms | 29.640 ms | 14.751 ms | 8.615 ms | 3.453 ms | 23.446 ms | 11.755 ms | 5.892 ms | — | 6.480 ms | 1.204 ms | 394.345 μs |
| add! scalar | Float32 64^3 | 43.970 μs | 455.288 μs | 232.258 μs | 121.544 μs | 20.621 μs | 367.263 μs | 186.292 μs | 94.691 μs | 85.391 μs | 1.599 ms | 291.603 μs | 109.021 μs |
| add! scalar | Float64 128^3 | 1.546 ms | 3.635 ms | 1.861 ms | 1.118 ms | 326.553 μs | 2.931 ms | 1.472 ms | 739.277 μs | 354.693 μs | 2.024 ms | 379.045 μs | 169.933 μs |
| add! scalar | Float64 256^3 | 17.845 ms | 29.749 ms | 16.543 ms | 15.814 ms | 9.894 ms | 23.471 ms | 12.618 ms | 7.553 ms | — | 5.550 ms | 1.230 ms | 609.449 μs |
| add! scalar | Float64 64^3 | 85.313 μs | 462.446 μs | 235.816 μs | 122.582 μs | 40.130 μs | 367.624 μs | 186.082 μs | 95.091 μs | 83.741 μs | 1.494 ms | 370.453 μs | 130.341 μs |
| combine! vec | Float32 128^3 | 2.816 ms | 17.835 ms | 8.979 ms | 4.746 ms | — | — | — | — | — | — | 661.005 μs | — |
| combine! vec | Float32 256^3 | 26.999 ms | 144.556 ms | 72.271 ms | 37.146 ms | — | — | — | — | — | — | 3.456 ms | — |
| combine! vec | Float32 64^3 | 129.781 μs | 2.217 ms | 1.120 ms | 574.521 μs | — | — | — | — | — | — | 335.255 μs | — |
| combine! vec | Float64 128^3 | 6.332 ms | 17.801 ms | 9.019 ms | 5.673 ms | — | — | — | — | — | — | 811.828 μs | — |
| combine! vec | Float64 256^3 | 53.973 ms | 145.694 ms | 73.271 ms | 47.019 ms | — | — | — | — | — | — | 4.040 ms | — |
| combine! vec | Float64 64^3 | 281.069 μs | 2.253 ms | 1.127 ms | 584.981 μs | — | — | — | — | — | — | 339.757 μs | — |
| cross! | Float32 128^3 | 4.928 ms | 16.678 ms | 8.579 ms | 4.349 ms | 2.975 ms | 12.737 ms | 6.393 ms | 3.222 ms | 1.223 ms | 3.445 ms | 741.028 μs | 266.014 μs |
| cross! | Float32 256^3 | 44.645 ms | 136.328 ms | 68.726 ms | 36.464 ms | 35.853 ms | 102.465 ms | 52.385 ms | 25.780 ms | — | 14.690 ms | 3.372 ms | 1.359 ms |
| cross! | Float32 64^3 | 430.613 μs | 2.102 ms | 1.060 ms | 544.918 μs | 382.294 μs | 1.597 ms | 806.859 μs | 413.294 μs | 219.582 μs | 1.665 ms | 194.002 μs | 131.751 μs |
| cross! | Float64 128^3 | 10.318 ms | 16.153 ms | 9.063 ms | 8.561 ms | 5.760 ms | 12.868 ms | 6.423 ms | 3.237 ms | 1.263 ms | 2.603 ms | 799.815 μs | 417.918 μs |
| cross! | Float64 256^3 | 87.542 ms | 135.657 ms | 78.456 ms | 71.364 ms | 48.429 ms | 104.460 ms | 51.802 ms | 41.265 ms | — | 15.625 ms | 3.951 ms | 2.626 ms |
| cross! | Float64 64^3 | 477.981 μs | 1.969 ms | 1.025 ms | 527.981 μs | 395.645 μs | 1.599 ms | 815.679 μs | 416.314 μs | 216.592 μs | 1.846 ms | 359.561 μs | 144.521 μs |
| det! tensor | Float32 128^3 | 10.987 ms | 13.761 ms | 7.122 ms | 3.557 ms | — | — | — | — | — | — | 611.298 μs | — |
| det! tensor | Float32 256^3 | 93.250 ms | 114.377 ms | 57.806 ms | 30.451 ms | — | — | — | — | — | — | 2.725 ms | — |
| det! tensor | Float32 64^3 | 1.297 ms | 1.715 ms | 858.108 μs | 443.314 μs | — | — | — | — | — | — | 343.669 μs | — |
| det! tensor | Float64 128^3 | 11.869 ms | 14.164 ms | 7.146 ms | 5.213 ms | — | — | — | — | — | — | 863.681 μs | — |
| det! tensor | Float64 256^3 | 96.261 ms | 114.937 ms | 60.442 ms | 46.605 ms | — | — | — | — | — | — | 3.670 ms | — |
| det! tensor | Float64 64^3 | 1.370 ms | 1.700 ms | 876.781 μs | 448.779 μs | — | — | — | — | — | — | 363.869 μs | — |
| dot! vec.vec | Float32 128^3 | 2.845 ms | 6.781 ms | 3.477 ms | 1.797 ms | 2.458 ms | 5.203 ms | 2.622 ms | 1.316 ms | 538.855 μs | 2.430 ms | 428.856 μs | 185.093 μs |
| dot! vec.vec | Float32 256^3 | 24.880 ms | 54.576 ms | 28.409 ms | 16.191 ms | 25.951 ms | 43.509 ms | 22.417 ms | 10.840 ms | — | 9.651 ms | 1.580 ms | 690.329 μs |
| dot! vec.vec | Float32 64^3 | 335.576 μs | 853.337 μs | 424.365 μs | 222.250 μs | 308.583 μs | 649.877 μs | 327.704 μs | 166.322 μs | 112.901 μs | 1.663 ms | 303.591 μs | 124.771 μs |
| dot! vec.vec | Float64 128^3 | 4.571 ms | 6.749 ms | 3.730 ms | 3.376 ms | 3.439 ms | 5.306 ms | 2.644 ms | 1.339 ms | 618.906 μs | 2.505 ms | 533.841 μs | 259.945 μs |
| dot! vec.vec | Float64 256^3 | 42.263 ms | 56.172 ms | 33.798 ms | 31.532 ms | 31.568 ms | 49.495 ms | 21.697 ms | 18.526 ms | — | 9.784 ms | 2.043 ms | 1.299 ms |
| dot! vec.vec | Float64 64^3 | 342.211 μs | 852.801 μs | 428.310 μs | 220.958 μs | 318.263 μs | 654.296 μs | 331.303 μs | 169.632 μs | 127.611 μs | 1.656 ms | 162.125 μs | 141.801 μs |
| mul! tensor.vec | Float32 128^3 | 9.135 ms | 21.169 ms | 10.910 ms | 5.677 ms | 7.451 ms | 16.037 ms | 8.016 ms | 4.031 ms | 1.525 ms | 4.295 ms | 918.199 μs | 322.895 μs |
| mul! tensor.vec | Float32 256^3 | 79.033 ms | 171.834 ms | 87.930 ms | 50.881 ms | 72.057 ms | 129.060 ms | 68.181 ms | 33.241 ms | — | 16.892 ms | 4.152 ms | 1.835 ms |
| mul! tensor.vec | Float32 64^3 | 1.011 ms | 2.628 ms | 1.330 ms | 686.859 μs | 917.269 μs | 2.004 ms | 1.022 ms | 516.635 μs | 255.702 μs | 1.882 ms | 320.574 μs | 139.951 μs |
| mul! tensor.vec | Float64 128^3 | 15.002 ms | 21.129 ms | 12.108 ms | 11.257 ms | 11.121 ms | 16.835 ms | 8.302 ms | 4.165 ms | 1.748 ms | 4.757 ms | 982.624 μs | 534.231 μs |
| mul! tensor.vec | Float64 256^3 | 124.860 ms | 175.649 ms | 102.925 ms | 95.531 ms | 81.798 ms | 145.451 ms | 65.681 ms | 55.305 ms | — | 17.818 ms | 5.402 ms | 3.646 ms |
| mul! tensor.vec | Float64 64^3 | 1.182 ms | 2.558 ms | 1.329 ms | 699.429 μs | 936.140 μs | 2.008 ms | 1.008 ms | 517.485 μs | 280.183 μs | 1.951 ms | 449.785 μs | 183.921 μs |
| norm! vec | Float32 128^3 | 769.840 μs | 4.963 ms | 2.529 ms | 1.296 ms | 215.653 μs | 3.771 ms | 1.887 ms | 951.099 μs | 411.304 μs | 2.110 ms | 398.094 μs | 169.582 μs |
| norm! vec | Float32 256^3 | 10.942 ms | 39.879 ms | 20.810 ms | 10.577 ms | 5.290 ms | 30.345 ms | 15.286 ms | 7.659 ms | — | 7.304 ms | 1.216 ms | 443.575 μs |
| norm! vec | Float32 64^3 | 56.961 μs | 621.762 μs | 313.206 μs | 161.352 μs | 31.180 μs | 471.814 μs | 237.072 μs | 120.361 μs | 100.251 μs | 1.526 ms | 293.826 μs | 117.191 μs |
| norm! vec | Float64 128^3 | 2.262 ms | 5.010 ms | 2.563 ms | 1.782 ms | 482.055 μs | 3.927 ms | 1.981 ms | 999.750 μs | 463.344 μs | 1.434 ms | 594.819 μs | 205.644 μs |
| norm! vec | Float64 256^3 | 22.598 ms | 41.441 ms | 22.175 ms | 19.803 ms | 11.013 ms | 31.835 ms | 16.067 ms | 10.221 ms | — | 9.850 ms | 2.466 ms | 767.251 μs |
| norm! vec | Float64 64^3 | 160.955 μs | 628.865 μs | 321.851 μs | 167.630 μs | 56.020 μs | 493.305 μs | 248.733 μs | 126.071 μs | 101.231 μs | 1.681 ms | 330.640 μs | 142.061 μs |
| tr! tensor | Float32 128^3 | 770.255 μs | 4.438 ms | 2.249 ms | 1.167 ms | — | — | — | — | — | — | 381.081 μs | — |
| tr! tensor | Float32 256^3 | 10.961 ms | 36.969 ms | 18.241 ms | 10.382 ms | — | — | — | — | — | — | 1.214 ms | — |
| tr! tensor | Float32 64^3 | 53.848 μs | 559.549 μs | 281.380 μs | 145.533 μs | — | — | — | — | — | — | 301.965 μs | — |
| tr! tensor | Float64 128^3 | 2.239 ms | 4.366 ms | 2.258 ms | 1.758 ms | — | — | — | — | — | — | 441.365 μs | — |
| tr! tensor | Float64 256^3 | 22.145 ms | 36.362 ms | 20.738 ms | 19.678 ms | — | — | — | — | — | — | 1.340 ms | — |
| tr! tensor | Float64 64^3 | 107.309 μs | 550.708 μs | 276.150 μs | 145.507 μs | — | — | — | — | — | — | 315.126 μs | — |

## operators

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.332 ms | 9.191 ms | 4.550 ms | 2.400 ms | 3.760 ms | 6.531 ms | 3.291 ms | 1.662 ms | 697.807 μs | 2.544 ms | 551.324 μs | 198.113 μs |
| curl! vec->vec | Float32 256^3 | 43.101 ms | 72.367 ms | 36.899 ms | 25.627 ms | 30.581 ms | 51.797 ms | 26.006 ms | 13.329 ms | — | 10.865 ms | 1.982 ms | 873.101 μs |
| curl! vec->vec | Float32 64^3 | 644.070 μs | 1.158 ms | 585.317 μs | 310.884 μs | 495.096 μs | 841.331 μs | 427.605 μs | 224.533 μs | 182.902 μs | 1.646 ms | 174.757 μs | 123.311 μs |
| curl! vec->vec | Float64 128^3 | 6.542 ms | 9.174 ms | 5.281 ms | 4.185 ms | 3.538 ms | 6.784 ms | 3.408 ms | 1.723 ms | 824.588 μs | 3.153 ms | 750.075 μs | 302.865 μs |
| curl! vec->vec | Float64 256^3 | 58.089 ms | 73.095 ms | 49.179 ms | 40.722 ms | 36.774 ms | 53.961 ms | 27.353 ms | 25.771 ms | — | 13.647 ms | 3.489 ms | 1.643 ms |
| curl! vec->vec | Float64 64^3 | 524.406 μs | 1.127 ms | 582.203 μs | 304.882 μs | 450.445 μs | 888.829 μs | 454.745 μs | 241.802 μs | 186.242 μs | 1.786 ms | 393.548 μs | 157.981 μs |
| divergence! vec->scalar | Float32 128^3 | 3.662 ms | 3.649 ms | 1.890 ms | 993.554 μs | 3.350 ms | 2.742 ms | 1.371 ms | 696.577 μs | 326.353 μs | 1.957 ms | 400.152 μs | 182.493 μs |
| divergence! vec->scalar | Float32 256^3 | 28.920 ms | 29.850 ms | 15.081 ms | 9.627 ms | 26.576 ms | 21.747 ms | 10.943 ms | 5.576 ms | — | 5.523 ms | 1.230 ms | 447.575 μs |
| divergence! vec->scalar | Float32 64^3 | 427.458 μs | 465.493 μs | 239.116 μs | 125.776 μs | 436.644 μs | 361.755 μs | 180.112 μs | 93.511 μs | 93.900 μs | 1.537 ms | 325.554 μs | 114.121 μs |
| divergence! vec->scalar | Float64 128^3 | 3.676 ms | 3.697 ms | 2.077 ms | 1.800 ms | 3.340 ms | 2.800 ms | 1.400 ms | 707.057 μs | 407.644 μs | 2.306 ms | 448.700 μs | 198.633 μs |
| divergence! vec->scalar | Float64 256^3 | 32.844 ms | 31.194 ms | 21.140 ms | 19.566 ms | 26.981 ms | 22.273 ms | 11.148 ms | 10.265 ms | — | 7.090 ms | 1.844 ms | 784.760 μs |
| divergence! vec->scalar | Float64 64^3 | 415.329 μs | 468.003 μs | 235.837 μs | 123.143 μs | 437.505 μs | 367.054 μs | 189.772 μs | 96.961 μs | 103.111 μs | 344.869 μs | 324.934 μs | 137.961 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.623 ms | 4.665 ms | 2.354 ms | 1.231 ms | — | — | — | — | — | — | 546.243 μs | — |
| divergence!∘kernel vec->scalar | Float32 256^3 | 35.646 ms | 37.462 ms | 19.009 ms | 11.723 ms | — | — | — | — | — | — | 1.092 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 550.278 μs | 583.344 μs | 297.431 μs | 156.406 μs | — | — | — | — | — | — | 283.459 μs | — |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.807 ms | 4.621 ms | 2.647 ms | 2.353 ms | — | — | — | — | — | — | 608.926 μs | — |
| divergence!∘kernel vec->scalar | Float64 256^3 | 40.931 ms | 38.067 ms | 25.245 ms | 23.779 ms | — | — | — | — | — | — | 2.117 ms | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 552.953 μs | 582.643 μs | 301.498 μs | 156.491 μs | — | — | — | — | — | — | 153.083 μs | — |
| gradient! scalar->vec | Float32 128^3 | 3.878 ms | 6.343 ms | 3.184 ms | 1.645 ms | 1.921 ms | 4.528 ms | 2.279 ms | 1.148 ms | 560.525 μs | 2.377 ms | 437.501 μs | 180.183 μs |
| gradient! scalar->vec | Float32 256^3 | 32.209 ms | 49.818 ms | 25.284 ms | 18.636 ms | 15.485 ms | 35.933 ms | 18.076 ms | 9.107 ms | — | 7.929 ms | 1.627 ms | 639.438 μs |
| gradient! scalar->vec | Float32 64^3 | 482.604 μs | 792.999 μs | 408.421 μs | 217.904 μs | 248.332 μs | 580.708 μs | 294.063 μs | 153.702 μs | 133.261 μs | 1.681 ms | 361.502 μs | 118.521 μs |
| gradient! scalar->vec | Float64 128^3 | 4.097 ms | 6.177 ms | 3.420 ms | 2.271 ms | 1.878 ms | 4.598 ms | 2.299 ms | 1.178 ms | 605.225 μs | 2.717 ms | 678.031 μs | 207.224 μs |
| gradient! scalar->vec | Float64 256^3 | 41.972 ms | 50.278 ms | 33.673 ms | 27.350 ms | 20.810 ms | 36.563 ms | 18.433 ms | 16.819 ms | — | 10.338 ms | 2.694 ms | 1.159 ms |
| gradient! scalar->vec | Float64 64^3 | 372.986 μs | 803.740 μs | 402.820 μs | 216.375 μs | 242.793 μs | 590.836 μs | 300.873 μs | 156.552 μs | 153.172 μs | 1.872 ms | 375.405 μs | 146.581 μs |
| helmholtz! vec->vec | Float32 128^3 | 5.347 ms | 2.685 ms | 1.515 ms | 1.301 ms | 21.192 ms | 17.364 ms | 8.724 ms | 4.389 ms | 1.480 ms | 4.174 ms | 208.114 μs | 271.534 μs |
| helmholtz! vec->vec | Float32 256^3 | 43.018 ms | 22.153 ms | 18.285 ms | 17.934 ms | 167.460 ms | 137.938 ms | 69.149 ms | 34.922 ms | — | 16.637 ms | 1.071 ms | 1.190 ms |
| helmholtz! vec->vec | Float32 64^3 | 709.122 μs | 357.658 μs | 187.864 μs | 99.692 μs | 2.784 ms | 2.242 ms | 1.126 ms | 575.606 μs | 286.333 μs | 1.935 ms | 321.721 μs | 141.431 μs |
| helmholtz! vec->vec | Float64 128^3 | 6.186 ms | 4.285 ms | 3.888 ms | 3.745 ms | 21.853 ms | 17.571 ms | 8.815 ms | 4.447 ms | 1.802 ms | 5.921 ms | 681.569 μs | 538.670 μs |
| helmholtz! vec->vec | Float64 256^3 | 52.605 ms | 39.695 ms | 36.920 ms | 35.988 ms | 174.081 ms | 139.701 ms | 69.985 ms | 35.784 ms | — | 18.240 ms | 2.817 ms | 3.037 ms |
| helmholtz! vec->vec | Float64 64^3 | 785.322 μs | 395.868 μs | 200.525 μs | 109.877 μs | 2.871 ms | 2.283 ms | 1.176 ms | 601.876 μs | 342.613 μs | 2.260 ms | 381.048 μs | 219.452 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 6.384 ms | 3.279 ms | 1.877 ms | 1.682 ms | — | — | — | — | — | — | 206.405 μs | — |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 51.203 ms | 26.002 ms | 20.246 ms | 19.805 ms | — | — | — | — | — | — | 969.713 μs | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 840.993 μs | 434.448 μs | 222.258 μs | 115.997 μs | — | — | — | — | — | — | 346.382 μs | — |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 7.169 ms | 4.962 ms | 4.484 ms | 4.381 ms | — | — | — | — | — | — | 814.421 μs | — |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 60.187 ms | 43.988 ms | 40.900 ms | 39.777 ms | — | — | — | — | — | — | 3.617 ms | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 933.104 μs | 462.957 μs | 236.175 μs | 124.703 μs | — | — | — | — | — | — | 374.563 μs | — |
| laplacian! scalar | Float32 128^3 | 2.061 ms | 2.746 ms | 1.352 ms | 721.537 μs | 2.145 ms | 2.121 ms | 1.065 ms | 536.235 μs | 265.103 μs | 1.910 ms | 357.451 μs | 153.513 μs |
| laplacian! scalar | Float32 256^3 | 16.755 ms | 22.106 ms | 11.152 ms | 6.085 ms | 17.103 ms | 16.914 ms | 8.482 ms | 4.257 ms | — | 5.490 ms | 946.817 μs | 291.864 μs |
| laplacian! scalar | Float32 64^3 | 252.574 μs | 346.110 μs | 176.807 μs | 93.179 μs | 275.083 μs | 270.323 μs | 136.231 μs | 70.100 μs | 83.431 μs | 1.563 ms | 125.781 μs | 106.850 μs |
| laplacian! scalar | Float64 128^3 | 2.114 ms | 2.769 ms | 1.409 ms | 730.468 μs | 2.202 ms | 2.238 ms | 1.123 ms | 565.435 μs | 278.082 μs | 1.957 ms | 361.040 μs | 153.273 μs |
| laplacian! scalar | Float64 256^3 | 17.876 ms | 22.542 ms | 13.154 ms | 10.094 ms | 17.727 ms | 17.820 ms | 8.946 ms | 4.868 ms | — | 4.740 ms | 1.007 ms | 452.256 μs |
| laplacian! scalar | Float64 64^3 | 257.704 μs | 346.854 μs | 181.490 μs | 95.390 μs | 281.713 μs | 284.443 μs | 143.281 μs | 73.681 μs | 84.420 μs | 1.586 ms | 311.696 μs | 135.841 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 13.277 ms | 24.177 ms | 12.287 ms | 6.586 ms | — | — | — | — | — | — | 918.561 μs | — |
| symmetric_gradient! vec->tensor | Float32 256^3 | 105.902 ms | 188.498 ms | 97.058 ms | 71.424 ms | — | — | — | — | — | — | 4.854 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.561 ms | 3.069 ms | 1.563 ms | 833.393 μs | — | — | — | — | — | — | 467.259 μs | — |
| symmetric_gradient! vec->tensor | Float64 128^3 | 18.609 ms | 24.173 ms | 15.134 ms | 11.540 ms | — | — | — | — | — | — | 1.452 ms | — |
| symmetric_gradient! vec->tensor | Float64 256^3 | 155.770 ms | 192.065 ms | 140.340 ms | 107.575 ms | — | — | — | — | — | — | 8.458 ms | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.201 ms | 3.003 ms | 1.552 ms | 822.419 μs | — | — | — | — | — | — | 503.754 μs | — |

## convolution

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.849 ms | 2.252 ms | 1.117 ms | 583.670 μs | 1.365 ms | 1.737 ms | 872.749 μs | 440.275 μs | 296.642 μs | 1.855 ms | 274.024 μs | 149.562 μs |
| assignment_window | Float32 256^3 | 28.203 ms | 24.888 ms | 9.162 ms | 4.771 ms | 17.806 ms | 18.025 ms | 9.132 ms | 4.711 ms | — | 3.952 ms | 906.052 μs | 272.023 μs |
| assignment_window | Float32 64^3 | 230.412 μs | 284.137 μs | 145.571 μs | 79.361 μs | 175.962 μs | 223.263 μs | 113.092 μs | 59.221 μs | 138.651 μs | 1.640 ms | 408.218 μs | 124.901 μs |
| assignment_window | Float64 128^3 | 1.923 ms | 2.206 ms | 1.137 ms | 684.038 μs | 1.549 ms | 1.776 ms | 889.039 μs | 453.375 μs | 306.863 μs | 1.901 ms | 456.909 μs | 146.993 μs |
| assignment_window | Float64 256^3 | 42.182 ms | 32.063 ms | 16.713 ms | 9.242 ms | 27.067 ms | 22.408 ms | 11.461 ms | 6.640 ms | — | 4.237 ms | 975.561 μs | 301.054 μs |
| assignment_window | Float64 64^3 | 244.355 μs | 282.564 μs | 146.029 μs | 83.786 μs | 198.702 μs | 228.782 μs | 116.331 μs | 60.841 μs | 141.232 μs | 1.542 ms | 221.844 μs | 144.111 μs |
| combine!∘kernel vector | Float32 128^3 | 8.757 ms | 11.414 ms | 5.701 ms | 2.921 ms | — | — | — | — | — | — | 514.875 μs | — |
| combine!∘kernel vector | Float32 256^3 | 70.758 ms | 90.386 ms | 45.671 ms | 24.701 ms | — | — | — | — | — | — | 2.214 ms | — |
| combine!∘kernel vector | Float32 64^3 | 1.189 ms | 1.416 ms | 720.281 μs | 369.248 μs | — | — | — | — | — | — | 325.364 μs | — |
| combine!∘kernel vector | Float64 128^3 | 10.046 ms | 11.079 ms | 5.966 ms | 5.261 ms | — | — | — | — | — | — | 766.781 μs | — |
| combine!∘kernel vector | Float64 256^3 | 82.613 ms | 91.120 ms | 51.979 ms | 46.381 ms | — | — | — | — | — | — | 3.711 ms | — |
| combine!∘kernel vector | Float64 64^3 | 1.196 ms | 1.410 ms | 719.913 μs | 365.096 μs | — | — | — | — | — | — | 353.470 μs | — |
| convolve! scalar | Float32 128^3 | 1.642 ms | 2.071 ms | 1.064 ms | 545.465 μs | 913.799 μs | 1.498 ms | 752.438 μs | 380.064 μs | 220.032 μs | 1.755 ms | 158.468 μs | 147.812 μs |
| convolve! scalar | Float32 256^3 | 13.765 ms | 17.286 ms | 8.580 ms | 7.769 ms | 7.601 ms | 11.890 ms | 5.961 ms | 3.010 ms | — | 3.659 ms | 720.153 μs | 363.365 μs |
| convolve! scalar | Float32 64^3 | 201.161 μs | 268.019 μs | 135.606 μs | 72.302 μs | 116.911 μs | 191.832 μs | 97.081 μs | 50.690 μs | 78.951 μs | 1.480 ms | 303.195 μs | 104.770 μs |
| convolve! scalar | Float64 128^3 | 1.960 ms | 2.117 ms | 1.319 ms | 996.734 μs | 1.006 ms | 1.665 ms | 834.848 μs | 421.684 μs | 302.553 μs | 1.784 ms | 211.581 μs | 174.253 μs |
| convolve! scalar | Float64 256^3 | 19.251 ms | 18.151 ms | 13.824 ms | 12.228 ms | 10.490 ms | 13.254 ms | 7.561 ms | 7.607 ms | — | 4.442 ms | 1.058 ms | 613.078 μs |
| convolve! scalar | Float64 64^3 | 179.774 μs | 260.094 μs | 133.456 μs | 71.629 μs | 125.651 μs | 213.022 μs | 106.812 μs | 55.770 μs | 78.591 μs | 1.618 ms | 337.239 μs | 116.181 μs |
| convolve! vector | Float32 128^3 | 6.067 ms | 9.107 ms | 4.604 ms | 2.378 ms | 4.552 ms | 6.777 ms | 3.398 ms | 1.705 ms | 731.727 μs | 2.557 ms | 472.728 μs | 187.513 μs |
| convolve! vector | Float32 256^3 | 49.271 ms | 71.294 ms | 36.739 ms | 23.820 ms | 36.088 ms | 53.773 ms | 26.998 ms | 13.525 ms | — | 10.821 ms | 1.843 ms | 875.680 μs |
| convolve! vector | Float32 64^3 | 736.726 μs | 1.139 ms | 583.108 μs | 299.989 μs | 582.816 μs | 859.261 μs | 432.564 μs | 218.742 μs | 161.751 μs | 1.595 ms | 314.803 μs | 112.681 μs |
| convolve! vector | Float64 128^3 | 7.164 ms | 9.344 ms | 5.209 ms | 4.338 ms | 4.806 ms | 6.946 ms | 3.487 ms | 1.755 ms | 792.657 μs | 2.910 ms | 640.119 μs | 295.715 μs |
| convolve! vector | Float64 256^3 | 61.696 ms | 76.413 ms | 47.698 ms | 40.195 ms | 42.000 ms | 55.107 ms | 27.776 ms | 24.260 ms | — | 12.297 ms | 2.764 ms | 1.635 ms |
| convolve! vector | Float64 64^3 | 704.772 μs | 1.148 ms | 588.441 μs | 303.859 μs | 597.307 μs | 882.528 μs | 443.495 μs | 224.613 μs | 167.451 μs | 1.655 ms | 357.520 μs | 129.661 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.724 ms | 3.924 ms | 2.466 ms | 1.347 ms | — | — | — | — | — | — | 386.470 μs | — |
| exponential_convolve! scalar | Float32 256^3 | 34.753 ms | 24.909 ms | 13.162 ms | 7.389 ms | — | — | — | — | — | — | 846.822 μs | — |
| exponential_convolve! scalar | Float32 64^3 | 2.197 ms | 1.310 ms | 698.000 μs | 362.265 μs | — | — | — | — | — | — | 355.701 μs | — |
| exponential_convolve! scalar | Float64 128^3 | 8.246 ms | 5.664 ms | 3.308 ms | 1.972 ms | — | — | — | — | — | — | 452.793 μs | — |
| exponential_convolve! scalar | Float64 256^3 | 56.283 ms | 40.122 ms | 21.475 ms | 12.566 ms | — | — | — | — | — | — | 1.684 ms | — |
| exponential_convolve! scalar | Float64 64^3 | 737.673 μs | 563.050 μs | 285.564 μs | 150.037 μs | — | — | — | — | — | — | 332.052 μs | — |
| exponential_convolve! vector | Float32 128^3 | 19.113 ms | 15.232 ms | 8.154 ms | 4.885 ms | — | — | — | — | — | — | 669.992 μs | — |
| exponential_convolve! vector | Float32 256^3 | 118.377 ms | 97.947 ms | 50.681 ms | 26.940 ms | — | — | — | — | — | — | 2.256 ms | — |
| exponential_convolve! vector | Float32 64^3 | 6.918 ms | 4.417 ms | 2.307 ms | 1.218 ms | — | — | — | — | — | — | 336.138 μs | — |
| exponential_convolve! vector | Float64 128^3 | 27.195 ms | 20.847 ms | 11.051 ms | 6.487 ms | — | — | — | — | — | — | 928.874 μs | — |
| exponential_convolve! vector | Float64 256^3 | 186.872 ms | 146.013 ms | 76.188 ms | 40.859 ms | — | — | — | — | — | — | 4.924 ms | — |
| exponential_convolve! vector | Float64 64^3 | 2.535 ms | 2.166 ms | 1.110 ms | 568.887 μs | — | — | — | — | — | — | 429.764 μs | — |
| spectral_band | Float32 128^3 | 4.200 ms | 3.422 ms | 1.715 ms | 886.555 μs | 3.860 ms | 2.627 ms | 1.318 ms | 663.667 μs | 334.154 μs | 2.050 ms | 400.569 μs | 169.452 μs |
| spectral_band | Float32 256^3 | 46.789 ms | 33.835 ms | 13.683 ms | 7.165 ms | 39.125 ms | 24.889 ms | 12.675 ms | 6.651 ms | — | 6.344 ms | 986.036 μs | 320.624 μs |
| spectral_band | Float32 64^3 | 523.213 μs | 427.685 μs | 219.260 μs | 116.255 μs | 492.555 μs | 335.924 μs | 169.182 μs | 86.430 μs | 106.071 μs | 1.537 ms | 142.500 μs | 124.611 μs |
| spectral_band | Float64 128^3 | 4.273 ms | 3.403 ms | 1.740 ms | 942.494 μs | 3.971 ms | 2.648 ms | 1.347 ms | 676.757 μs | 361.113 μs | 2.105 ms | 432.997 μs | 160.013 μs |
| spectral_band | Float64 256^3 | 60.189 ms | 41.285 ms | 21.167 ms | 11.444 ms | 47.787 ms | 29.698 ms | 15.343 ms | 7.968 ms | — | 5.611 ms | 1.281 ms | 331.105 μs |
| spectral_band | Float64 64^3 | 523.418 μs | 433.651 μs | 221.418 μs | 123.355 μs | 505.345 μs | 346.093 μs | 172.012 μs | 87.831 μs | 110.411 μs | 1.651 ms | 347.331 μs | 136.321 μs |
| spectral_cutoff | Float32 128^3 | 4.207 ms | 3.352 ms | 1.718 ms | 878.672 μs | 3.863 ms | 2.637 ms | 1.323 ms | 664.357 μs | 331.623 μs | 2.046 ms | 404.955 μs | 186.603 μs |
| spectral_cutoff | Float32 256^3 | 46.822 ms | 34.547 ms | 13.809 ms | 7.206 ms | 38.539 ms | 25.019 ms | 12.609 ms | 6.389 ms | — | 5.403 ms | 1.068 ms | 326.044 μs |
| spectral_cutoff | Float32 64^3 | 509.374 μs | 427.396 μs | 220.422 μs | 116.163 μs | 492.245 μs | 336.094 μs | 169.322 μs | 86.451 μs | 108.881 μs | 1.625 ms | 322.911 μs | 135.961 μs |
| spectral_cutoff | Float64 128^3 | 4.197 ms | 3.462 ms | 1.738 ms | 974.235 μs | 3.971 ms | 2.667 ms | 1.349 ms | 677.127 μs | 351.793 μs | 2.120 ms | 405.973 μs | 155.713 μs |
| spectral_cutoff | Float64 256^3 | 59.604 ms | 41.886 ms | 21.099 ms | 11.370 ms | 48.114 ms | 30.271 ms | 15.329 ms | 8.097 ms | — | 5.621 ms | 1.287 ms | 332.894 μs |
| spectral_cutoff | Float64 64^3 | 534.454 μs | 433.480 μs | 222.257 μs | 118.498 μs | 505.356 μs | 337.613 μs | 171.412 μs | 87.781 μs | 117.711 μs | 1.647 ms | 355.066 μs | 137.101 μs |
| squared_wavenumber_field | Float32 128^3 | 1.841 ms | 2.230 ms | 1.130 ms | 579.126 μs | 1.375 ms | 1.735 ms | 870.829 μs | 438.445 μs | 262.463 μs | 1.824 ms | 354.675 μs | 154.973 μs |
| squared_wavenumber_field | Float32 256^3 | 27.936 ms | 25.131 ms | 9.074 ms | 4.704 ms | 18.169 ms | 18.031 ms | 9.136 ms | 4.766 ms | — | 3.812 ms | 819.707 μs | 273.344 μs |
| squared_wavenumber_field | Float32 64^3 | 228.975 μs | 279.362 μs | 144.217 μs | 77.567 μs | 176.492 μs | 222.643 μs | 112.222 μs | 58.231 μs | 91.321 μs | 1.517 ms | 373.013 μs | 130.641 μs |
| squared_wavenumber_field | Float64 128^3 | 1.940 ms | 2.180 ms | 1.119 ms | 706.287 μs | 1.418 ms | 1.766 ms | 889.319 μs | 448.434 μs | 264.163 μs | 1.805 ms | 396.751 μs | 137.923 μs |
| squared_wavenumber_field | Float64 256^3 | 41.271 ms | 31.606 ms | 16.422 ms | 9.209 ms | 27.320 ms | 22.495 ms | 11.272 ms | 6.677 ms | — | 4.151 ms | 835.978 μs | 291.774 μs |
| squared_wavenumber_field | Float64 64^3 | 245.685 μs | 283.214 μs | 143.709 μs | 81.335 μs | 182.462 μs | 226.173 μs | 114.841 μs | 59.251 μs | 88.931 μs | 1.612 ms | 323.221 μs | 135.121 μs |
| translation_kernel | Float32 128^3 | 1.841 ms | 2.625 ms | 1.356 ms | 680.137 μs | — | — | — | — | — | — | 394.496 μs | — |
| translation_kernel | Float32 256^3 | 28.357 ms | 27.746 ms | 10.625 ms | 5.481 ms | — | — | — | — | — | — | 856.930 μs | — |
| translation_kernel | Float32 64^3 | 232.572 μs | 329.267 μs | 170.177 μs | 91.174 μs | — | — | — | — | — | — | 342.271 μs | — |
| translation_kernel | Float64 128^3 | 1.833 ms | 2.683 ms | 1.382 ms | 740.848 μs | — | — | — | — | — | — | 453.284 μs | — |
| translation_kernel | Float64 256^3 | 41.397 ms | 34.957 ms | 18.599 ms | 9.924 ms | — | — | — | — | — | — | 1.335 ms | — |
| translation_kernel | Float64 64^3 | 232.803 μs | 344.441 μs | 177.822 μs | 95.455 μs | — | — | — | — | — | — | 424.413 μs | — |

## transfer

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 28.940 ms | 14.161 ms | 7.801 ms | 4.725 ms | 20.853 ms | 11.029 ms | 5.952 ms | 3.423 ms | 2.280 ms | 4.864 ms | 774.794 μs | 252.174 μs |
| anterpolate! CatmullRom | Float32 256^3 | 445.713 ms | 228.844 ms | 123.921 ms | 78.168 ms | 176.847 ms | 89.325 ms | 44.949 ms | 24.016 ms | — | 17.932 ms | 3.198 ms | 2.942 ms |
| anterpolate! CatmullRom | Float32 64^3 | 3.249 ms | 1.874 ms | 1.208 ms | 913.384 μs | 2.518 ms | 1.456 ms | 935.760 μs | 654.917 μs | 116.972 μs | 2.057 ms | 434.815 μs | 131.113 μs |
| anterpolate! CatmullRom | Float64 128^3 | 34.542 ms | 16.274 ms | 8.112 ms | 4.894 ms | 21.972 ms | 11.525 ms | 6.192 ms | 3.569 ms | 2.691 ms | 4.862 ms | 881.660 μs | 274.315 μs |
| anterpolate! CatmullRom | Float64 256^3 | 552.915 ms | 290.910 ms | 166.179 ms | 117.563 ms | 258.358 ms | 137.187 ms | 67.971 ms | 36.100 ms | — | 19.810 ms | 4.031 ms | 4.734 ms |
| anterpolate! CatmullRom | Float64 64^3 | 3.425 ms | 1.926 ms | 1.277 ms | 954.485 μs | 2.529 ms | 1.487 ms | 983.911 μs | 692.987 μs | 185.312 μs | 2.004 ms | 356.139 μs | 173.741 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 206.639 ms | 103.232 ms | 53.744 ms | 30.000 ms | 160.133 ms | 80.565 ms | 40.662 ms | 21.833 ms | 12.241 ms | 15.478 ms | 3.480 ms | 1.037 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.514 s | 1.333 s | 796.348 ms | 531.881 ms | 1.288 s | 645.869 ms | 322.718 ms | 162.733 ms | — | 48.567 ms | 17.733 ms | 15.297 ms |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.599 ms | 13.313 ms | 8.357 ms | 5.699 ms | 19.895 ms | 10.611 ms | 6.466 ms | 4.342 ms | 486.825 μs | 5.959 ms | 1.345 ms | 349.318 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 231.324 ms | 111.720 ms | 56.905 ms | 31.151 ms | 160.707 ms | 80.695 ms | 40.637 ms | 21.655 ms | 13.808 ms | 16.564 ms | 4.326 ms | 1.207 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.830 s | 1.540 s | 962.001 ms | 675.882 ms | 1.411 s | 707.868 ms | 353.528 ms | 179.684 ms | — | 66.043 ms | 28.006 ms | 24.797 ms |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 25.461 ms | 13.667 ms | 8.610 ms | 5.857 ms | 19.937 ms | 10.750 ms | 6.559 ms | 4.416 ms | 825.268 μs | 5.503 ms | 1.808 ms | 389.723 μs |
| anterpolate! NUFFT | Float32 128^3 | 453.275 ms | 249.588 ms | 166.972 ms | 126.014 ms | 372.969 ms | 200.077 ms | 112.323 ms | 70.585 ms | 20.177 ms | 18.762 ms | 4.619 ms | 2.835 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.662 s | 2.590 s | 1.613 s | 1.206 s | 3.744 s | 2.000 s | 1.123 s | 680.883 ms | — | 120.799 ms | 32.116 ms | 28.979 ms |
| anterpolate! NUFFT | Float32 64^3 | 34.030 ms | 18.389 ms | 11.864 ms | 8.462 ms | 27.205 ms | 14.594 ms | 8.773 ms | 6.055 ms | 1.989 ms | 6.296 ms | 1.556 ms | 461.610 μs |
| anterpolate! NUFFT | Float64 128^3 | 582.314 ms | 366.883 ms | 244.533 ms | 194.140 ms | 422.537 ms | 240.277 ms | 150.063 ms | 104.317 ms | 30.358 ms | 22.503 ms | 9.419 ms | 6.593 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.518 s | 3.190 s | 2.065 s | 1.649 s | 3.583 s | 2.024 s | 1.224 s | 876.521 ms | — | 160.735 ms | 75.186 ms | 58.865 ms |
| anterpolate! NUFFT | Float64 64^3 | 41.043 ms | 22.676 ms | 15.325 ms | 11.878 ms | 33.377 ms | 17.921 ms | 11.006 ms | 7.424 ms | 3.892 ms | 8.203 ms | 2.551 ms | 889.407 μs |
| anterpolate! trilinear | Float32 128^3 | 4.622 ms | 2.326 ms | 1.425 ms | 934.458 μs | 4.653 ms | 2.487 ms | 1.412 ms | 863.518 μs | 460.884 μs | 2.018 ms | 399.236 μs | 121.032 μs |
| anterpolate! trilinear | Float32 256^3 | 90.598 ms | 49.168 ms | 28.838 ms | 22.504 ms | 41.312 ms | 22.200 ms | 11.420 ms | 6.642 ms | — | 6.631 ms | 935.853 μs | 775.850 μs |
| anterpolate! trilinear | Float32 64^3 | 495.629 μs | 323.836 μs | 226.273 μs | 176.552 μs | 370.394 μs | 254.673 μs | 168.842 μs | 126.031 μs | 70.080 μs | 1.565 ms | 307.708 μs | 97.612 μs |
| anterpolate! trilinear | Float64 128^3 | 5.575 ms | 2.810 ms | 1.660 ms | 1.144 ms | 6.020 ms | 3.434 ms | 1.852 ms | 1.143 ms | 596.666 μs | 1.980 ms | 394.307 μs | 152.283 μs |
| anterpolate! trilinear | Float64 256^3 | 98.538 ms | 56.188 ms | 38.006 ms | 30.037 ms | 70.853 ms | 38.849 ms | 19.761 ms | 11.336 ms | — | 6.838 ms | 986.761 μs | 1.172 ms |
| anterpolate! trilinear | Float64 64^3 | 519.589 μs | 362.857 μs | 268.310 μs | 211.923 μs | 379.424 μs | 259.482 μs | 177.962 μs | 135.031 μs | 83.721 μs | 1.554 ms | 319.743 μs | 136.291 μs |
| interpolate! CatmullRom | Float32 128^3 | 12.089 ms | 5.951 ms | 3.108 ms | 1.684 ms | 5.495 ms | 2.749 ms | 1.400 ms | 739.937 μs | 972.889 μs | 3.140 ms | 513.046 μs | 199.723 μs |
| interpolate! CatmullRom | Float32 256^3 | 302.879 ms | 156.419 ms | 83.584 ms | 53.267 ms | 53.387 ms | 27.758 ms | 13.126 ms | 7.564 ms | — | 14.577 ms | 1.580 ms | 971.232 μs |
| interpolate! CatmullRom | Float32 64^3 | 1.336 ms | 711.866 μs | 437.869 μs | 300.388 μs | 617.266 μs | 334.914 μs | 200.732 μs | 135.491 μs | 101.321 μs | 1.724 ms | 376.135 μs | 143.863 μs |
| interpolate! CatmullRom | Float64 128^3 | 16.595 ms | 7.290 ms | 3.708 ms | 2.001 ms | 5.709 ms | 2.914 ms | 1.445 ms | 771.688 μs | 1.411 ms | 2.789 ms | 665.788 μs | 255.045 μs |
| interpolate! CatmullRom | Float64 256^3 | 330.742 ms | 173.228 ms | 101.047 ms | 66.240 ms | 147.259 ms | 78.610 ms | 37.862 ms | 20.554 ms | — | 12.939 ms | 2.020 ms | 1.810 ms |
| interpolate! CatmullRom | Float64 64^3 | 1.386 ms | 755.180 μs | 461.670 μs | 321.818 μs | 668.337 μs | 358.264 μs | 213.892 μs | 144.652 μs | 166.201 μs | 1.759 ms | 432.806 μs | 188.241 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 77.538 ms | 38.641 ms | 19.795 ms | 10.740 ms | 42.689 ms | 21.291 ms | 10.715 ms | 5.626 ms | 5.370 ms | 14.027 ms | 2.087 ms | 558.278 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.640 s | 901.758 ms | 561.171 ms | 355.760 ms | 352.690 ms | 173.927 ms | 86.132 ms | 47.587 ms | — | 30.216 ms | 10.730 ms | 4.812 ms |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.968 ms | 4.733 ms | 2.883 ms | 1.938 ms | 5.095 ms | 2.700 ms | 1.624 ms | 1.074 ms | 688.416 μs | 3.166 ms | 1.072 ms | 321.917 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 98.748 ms | 47.842 ms | 24.998 ms | 13.674 ms | 41.667 ms | 20.925 ms | 10.457 ms | 5.541 ms | 8.105 ms | 9.517 ms | 2.329 ms | 887.696 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.991 s | 1.134 s | 751.721 ms | 481.652 ms | 578.370 ms | 306.975 ms | 148.010 ms | 77.610 ms | — | 28.103 ms | 10.354 ms | 10.360 ms |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.170 ms | 4.977 ms | 2.998 ms | 2.024 ms | 5.264 ms | 2.777 ms | 1.690 ms | 1.117 ms | 911.428 μs | 3.595 ms | 1.429 ms | 395.473 μs |
| interpolate! NUFFT | Float32 128^3 | 347.500 ms | 203.706 ms | 137.004 ms | 112.535 ms | 257.028 ms | 143.571 ms | 85.835 ms | 56.122 ms | 12.723 ms | 16.422 ms | 3.783 ms | 1.987 ms |
| interpolate! NUFFT | Float32 256^3 | 3.874 s | 2.238 s | 1.475 s | 1.063 s | 2.937 s | 1.628 s | 949.879 ms | 611.868 ms | — | 72.243 ms | 25.429 ms | 17.998 ms |
| interpolate! NUFFT | Float32 64^3 | 18.087 ms | 10.580 ms | 7.136 ms | 5.312 ms | 12.128 ms | 6.582 ms | 3.874 ms | 2.581 ms | 1.847 ms | 4.302 ms | 1.350 ms | 438.530 μs |
| interpolate! NUFFT | Float64 128^3 | 452.141 ms | 284.231 ms | 214.567 ms | 176.271 ms | 219.217 ms | 135.253 ms | 95.489 ms | 78.310 ms | 25.361 ms | 18.237 ms | 8.028 ms | 5.611 ms |
| interpolate! NUFFT | Float64 256^3 | 4.263 s | 2.553 s | 1.814 s | 1.465 s | 1.961 s | 1.219 s | 853.185 ms | 720.111 ms | — | 118.516 ms | 55.024 ms | 48.438 ms |
| interpolate! NUFFT | Float64 64^3 | 24.593 ms | 15.853 ms | 11.858 ms | 9.597 ms | 17.580 ms | 9.922 ms | 6.046 ms | 4.234 ms | 3.417 ms | 6.116 ms | 2.315 ms | 979.427 μs |
| interpolate! trilinear | Float32 128^3 | 2.029 ms | 1.050 ms | 549.552 μs | 296.572 μs | 1.331 ms | 664.388 μs | 335.243 μs | 183.922 μs | 255.582 μs | 1.719 ms | 366.430 μs | 152.143 μs |
| interpolate! trilinear | Float32 256^3 | 59.612 ms | 31.528 ms | 16.597 ms | 10.000 ms | 13.575 ms | 7.062 ms | 3.369 ms | 2.022 ms | — | 3.594 ms | 535.992 μs | 339.724 μs |
| interpolate! trilinear | Float32 64^3 | 234.257 μs | 128.294 μs | 80.945 μs | 56.025 μs | 149.291 μs | 79.761 μs | 47.460 μs | 33.220 μs | 65.160 μs | 1.448 ms | 312.795 μs | 109.693 μs |
| interpolate! trilinear | Float64 128^3 | 2.641 ms | 1.283 ms | 657.885 μs | 363.000 μs | 1.415 ms | 700.618 μs | 351.844 μs | 186.861 μs | 325.503 μs | 1.772 ms | 336.686 μs | 158.423 μs |
| interpolate! trilinear | Float64 256^3 | 64.721 ms | 35.808 ms | 22.236 ms | 14.456 ms | 32.357 ms | 17.772 ms | 8.296 ms | 4.164 ms | — | 4.014 ms | 845.229 μs | 481.356 μs |
| interpolate! trilinear | Float64 64^3 | 244.280 μs | 135.084 μs | 83.822 μs | 58.437 μs | 161.762 μs | 86.691 μs | 49.971 μs | 33.760 μs | 65.930 μs | 1.530 ms | 155.672 μs | 132.411 μs |

## reductions

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.263 ms | 7.083 ms | 7.566 ms | 7.786 ms | 11.990 ms | 13.760 ms | 15.113 ms | 14.452 ms | 2.099 ms | 27.761 ms | 839.031 μs | 572.029 μs |
| co-spectrum vec.vec | Float32 256^3 | 66.852 ms | 49.480 ms | 45.365 ms | 42.410 ms | 125.360 ms | 129.303 ms | 126.822 ms | 125.880 ms | — | 97.666 ms | 2.655 ms | 2.301 ms |
| co-spectrum vec.vec | Float32 64^3 | 1.076 ms | 1.308 ms | 1.519 ms | 1.587 ms | 1.417 ms | 1.793 ms | 2.345 ms | 2.290 ms | 491.824 μs | 17.761 ms | 588.948 μs | 255.715 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.678 ms | 6.316 ms | 5.875 ms | 5.423 ms | 15.557 ms | 16.843 ms | 17.184 ms | 18.092 ms | 2.194 ms | 29.708 ms | 28.650 ms | 719.653 μs |
| co-spectrum vec.vec | Float64 256^3 | 70.996 ms | 50.569 ms | 37.153 ms | 30.218 ms | 174.226 ms | 171.108 ms | 170.799 ms | 167.189 ms | — | 109.563 ms | 65.238 ms | 3.758 ms |
| co-spectrum vec.vec | Float64 64^3 | 1.090 ms | 953.007 μs | 917.569 μs | 1.012 ms | 1.601 ms | 1.943 ms | 2.311 ms | 2.378 ms | 482.135 μs | 16.075 ms | 14.991 ms | 321.642 μs |
| cross-correlation vec.vec | Float32 128^3 | 43.424 ms | 41.255 ms | 37.979 ms | 37.074 ms | 38.774 ms | 37.557 ms | 33.492 ms | 28.603 ms | 5.891 ms | 43.640 ms | 1.660 ms | 917.034 μs |
| cross-correlation vec.vec | Float32 256^3 | 639.849 ms | 502.028 ms | 357.431 ms | 295.912 ms | 861.180 ms | 659.471 ms | 441.512 ms | 358.471 ms | — | 186.915 ms | 9.711 ms | 8.697 ms |
| cross-correlation vec.vec | Float32 64^3 | 4.909 ms | 6.487 ms | 6.293 ms | 6.488 ms | 4.052 ms | 4.555 ms | 4.572 ms | 4.675 ms | 1.025 ms | 20.682 ms | 639.508 μs | 341.177 μs |
| cross-correlation vec.vec | Float64 128^3 | 86.193 ms | 68.910 ms | 57.258 ms | 44.975 ms | 85.105 ms | 74.059 ms | 55.275 ms | 43.245 ms | 9.144 ms | 52.055 ms | 45.585 ms | 2.504 ms |
| cross-correlation vec.vec | Float64 256^3 | 768.419 ms | 609.905 ms | 424.586 ms | 376.028 ms | 726.007 ms | 577.186 ms | 430.434 ms | 398.996 ms | — | 217.471 ms | 135.191 ms | 17.926 ms |
| cross-correlation vec.vec | Float64 64^3 | 6.074 ms | 6.567 ms | 6.174 ms | 6.112 ms | 5.035 ms | 5.279 ms | 4.561 ms | 4.889 ms | 1.557 ms | 20.881 ms | 24.603 ms | 487.193 μs |
| inner spectral | Float32 128^3 | 1.678 ms | 1.641 ms | 1.709 ms | 1.616 ms | 529.735 μs | 528.066 μs | 529.295 μs | 524.155 μs | 669.926 μs | 2.049 ms | 581.033 μs | 320.794 μs |
| inner spectral | Float32 256^3 | 17.465 ms | 17.199 ms | 18.705 ms | 18.166 ms | 7.649 ms | 7.652 ms | 7.742 ms | 7.813 ms | — | 3.999 ms | 1.082 ms | 815.789 μs |
| inner spectral | Float32 64^3 | 150.309 μs | 152.802 μs | 150.041 μs | 153.956 μs | 88.821 μs | 87.881 μs | 100.021 μs | 88.081 μs | 275.972 μs | 1.780 ms | 526.140 μs | 242.155 μs |
| inner spectral | Float64 128^3 | 3.257 ms | 3.187 ms | 3.197 ms | 3.189 ms | 597.726 μs | 606.158 μs | 613.916 μs | 634.607 μs | 811.337 μs | 2.410 ms | 766.894 μs | 413.997 μs |
| inner spectral | Float64 256^3 | 27.816 ms | 28.026 ms | 28.065 ms | 28.147 ms | 16.625 ms | 16.062 ms | 16.109 ms | 16.320 ms | — | 7.953 ms | 2.174 ms | 1.324 ms |
| inner spectral | Float64 64^3 | 122.532 μs | 121.474 μs | 122.266 μs | 128.574 μs | 68.861 μs | 66.871 μs | 67.101 μs | 68.091 μs | 293.003 μs | 1.765 ms | 518.559 μs | 274.833 μs |
| inner vec.vec | Float32 128^3 | 1.278 ms | 1.275 ms | 1.346 ms | 1.286 ms | 309.533 μs | 309.114 μs | 309.473 μs | 311.753 μs | 308.353 μs | 1.623 ms | 264.045 μs | 198.062 μs |
| inner vec.vec | Float32 256^3 | 13.684 ms | 13.563 ms | 13.391 ms | 13.360 ms | 6.050 ms | 5.808 ms | 6.138 ms | 5.925 ms | — | 3.382 ms | 650.639 μs | 609.978 μs |
| inner vec.vec | Float32 64^3 | 66.271 μs | 66.667 μs | 66.309 μs | 67.193 μs | 38.550 μs | 38.340 μs | 38.310 μs | 38.451 μs | 98.731 μs | 1.278 ms | 250.252 μs | 107.702 μs |
| inner vec.vec | Float64 128^3 | 2.255 ms | 2.286 ms | 2.292 ms | 2.273 ms | 216.622 μs | 227.493 μs | 229.242 μs | 233.282 μs | 552.615 μs | 1.860 ms | 264.629 μs | 299.995 μs |
| inner vec.vec | Float64 256^3 | 23.368 ms | 23.570 ms | 22.645 ms | 23.069 ms | 13.064 ms | 13.117 ms | 13.070 ms | 13.014 ms | — | 5.634 ms | 1.408 ms | 1.143 ms |
| inner vec.vec | Float64 64^3 | 27.538 μs | 29.558 μs | 32.952 μs | 35.172 μs | 10.340 μs | 10.400 μs | 10.350 μs | 10.600 μs | 162.792 μs | 1.434 ms | 250.809 μs | 175.991 μs |
| integral scalar | Float32 128^3 | 113.400 μs | 108.417 μs | 110.182 μs | 113.181 μs | 60.501 μs | 59.971 μs | 64.680 μs | 59.861 μs | 228.932 μs | 1.318 ms | 498.427 μs | 151.522 μs |
| integral scalar | Float32 256^3 | 2.178 ms | 2.178 ms | 2.148 ms | 2.198 ms | 485.704 μs | 563.666 μs | 532.045 μs | 488.255 μs | — | 9.002 ms | 1.689 ms | 314.534 μs |
| integral scalar | Float32 64^3 | 10.911 μs | 10.766 μs | 10.747 μs | 11.064 μs | 6.816 μs | 6.740 μs | 6.960 μs | 6.612 μs | 95.301 μs | 1.534 ms | 335.134 μs | 132.923 μs |
| integral scalar | Float64 128^3 | 243.528 μs | 256.377 μs | 243.628 μs | 237.094 μs | 124.201 μs | 120.522 μs | 120.051 μs | 119.631 μs | 221.812 μs | 2.553 ms | 408.667 μs | 161.673 μs |
| integral scalar | Float64 256^3 | 5.271 ms | 4.816 ms | 5.071 ms | 5.087 ms | 1.760 ms | 2.138 ms | 1.978 ms | 2.010 ms | — | 10.817 ms | 2.011 ms | 354.165 μs |
| integral scalar | Float64 64^3 | 26.364 μs | 27.281 μs | 26.233 μs | 28.818 μs | 14.920 μs | 15.971 μs | 15.000 μs | 15.451 μs | 95.391 μs | 1.583 ms | 342.341 μs | 154.421 μs |
| integral spectral vec | Float32 128^3 | 67.985 ns | 68.105 ns | 68.078 ns | 68.363 ns | — | — | — | — | — | — | 317.457 μs | — |
| integral spectral vec | Float32 256^3 | 67.784 ns | 69.094 ns | 68.335 ns | 69.317 ns | — | — | — | — | — | — | 299.775 μs | — |
| integral spectral vec | Float32 64^3 | 67.887 ns | 67.971 ns | 68.011 ns | 67.882 ns | — | — | — | — | — | — | 316.532 μs | — |
| integral spectral vec | Float64 128^3 | 70.912 ns | 69.573 ns | 69.502 ns | 69.698 ns | — | — | — | — | — | — | 313.854 μs | — |
| integral spectral vec | Float64 256^3 | 74.535 ns | 69.957 ns | 71.417 ns | 70.402 ns | — | — | — | — | — | — | 162.397 μs | — |
| integral spectral vec | Float64 64^3 | 69.870 ns | 69.400 ns | 69.279 ns | 68.970 ns | — | — | — | — | — | — | 303.750 μs | — |
| l2norm vec | Float32 128^3 | 496.324 μs | 523.511 μs | 511.792 μs | 501.651 μs | 167.442 μs | 168.762 μs | 166.502 μs | 165.951 μs | 196.632 μs | 1.582 ms | 262.024 μs | 136.632 μs |
| l2norm vec | Float32 256^3 | 7.000 ms | 7.170 ms | 6.756 ms | 6.885 ms | 2.225 ms | 2.336 ms | 2.158 ms | 2.181 ms | — | 3.219 ms | 567.486 μs | 391.384 μs |
| l2norm vec | Float32 64^3 | 40.460 μs | 42.598 μs | 42.232 μs | 41.715 μs | 19.101 μs | 22.200 μs | 22.001 μs | 19.121 μs | 85.641 μs | 1.361 ms | 247.590 μs | 108.832 μs |
| l2norm vec | Float64 128^3 | 767.805 μs | 759.195 μs | 765.750 μs | 791.552 μs | 63.270 μs | 63.871 μs | 64.031 μs | 62.730 μs | 344.333 μs | 1.876 ms | 382.666 μs | 236.474 μs |
| l2norm vec | Float64 256^3 | 11.220 ms | 11.435 ms | 11.451 ms | 11.758 ms | 5.524 ms | 5.535 ms | 5.607 ms | 5.580 ms | — | 5.670 ms | 1.275 ms | 679.359 μs |
| l2norm vec | Float64 64^3 | 16.464 μs | 16.203 μs | 16.743 μs | 16.332 μs | 3.454 μs | 3.819 μs | 3.993 μs | 3.949 μs | 134.871 μs | 1.402 ms | 101.913 μs | 189.801 μs |
| lpnorm vec Inf | Float32 128^3 | 1.406 ms | 5.670 ms | 3.066 ms | 1.897 ms | 455.955 μs | 3.996 ms | 2.136 ms | 1.200 ms | 592.145 μs | 3.080 ms | 671.607 μs | 209.653 μs |
| lpnorm vec Inf | Float32 256^3 | 23.026 ms | 49.984 ms | 27.046 ms | 15.439 ms | 18.715 ms | 40.097 ms | 22.566 ms | 12.973 ms | — | 13.216 ms | 2.615 ms | 651.667 μs |
| lpnorm vec Inf | Float32 64^3 | 101.323 μs | 671.481 μs | 364.136 μs | 217.019 μs | 60.141 μs | 500.836 μs | 266.633 μs | 151.242 μs | 155.751 μs | 1.641 ms | 384.937 μs | 153.753 μs |
| lpnorm vec Inf | Float64 128^3 | 3.314 ms | 6.433 ms | 3.909 ms | 3.233 ms | 1.197 ms | 4.446 ms | 2.497 ms | 1.494 ms | 660.476 μs | 3.883 ms | 892.140 μs | 272.844 μs |
| lpnorm vec Inf | Float64 256^3 | 46.830 ms | 61.856 ms | 34.920 ms | 23.496 ms | 35.573 ms | 52.801 ms | 29.682 ms | 19.870 ms | — | 14.730 ms | 4.731 ms | 1.037 ms |
| lpnorm vec Inf | Float64 64^3 | 247.350 μs | 769.630 μs | 451.701 μs | 281.444 μs | 112.031 μs | 544.806 μs | 305.383 μs | 181.662 μs | 166.092 μs | 1.711 ms | 414.213 μs | 184.882 μs |
| maximum scalar | Float32 128^3 | 343.179 μs | 342.185 μs | 341.855 μs | 343.284 μs | 232.573 μs | 223.673 μs | 231.822 μs | 224.672 μs | 223.322 μs | 2.331 ms | 499.085 μs | 143.102 μs |
| maximum scalar | Float32 256^3 | 2.908 ms | 2.940 ms | 2.925 ms | 2.891 ms | 1.847 ms | 1.970 ms | 1.923 ms | 1.852 ms | — | 9.121 ms | 1.595 ms | 306.264 μs |
| maximum scalar | Float32 64^3 | 42.654 μs | 42.641 μs | 42.642 μs | 42.640 μs | 28.820 μs | 28.010 μs | 28.850 μs | 28.880 μs | 101.731 μs | 1.564 ms | 356.605 μs | 133.393 μs |
| maximum scalar | Float64 128^3 | 557.677 μs | 565.583 μs | 560.615 μs | 550.517 μs | 436.694 μs | 440.385 μs | 444.825 μs | 432.835 μs | 244.072 μs | 2.772 ms | 590.993 μs | 206.254 μs |
| maximum scalar | Float64 256^3 | 6.803 ms | 6.341 ms | 6.531 ms | 6.571 ms | 4.785 ms | 4.385 ms | 4.006 ms | 4.110 ms | — | 12.659 ms | 2.596 ms | 376.635 μs |
| maximum scalar | Float64 64^3 | 65.465 μs | 65.207 μs | 65.402 μs | 66.478 μs | 54.720 μs | 55.000 μs | 54.841 μs | 55.010 μs | 99.451 μs | 1.634 ms | 362.143 μs | 163.542 μs |
| maximum(norm) vec | Float32 128^3 | 1.857 ms | 1.850 ms | 1.856 ms | 1.856 ms | — | — | — | — | — | — | 528.932 μs | — |
| maximum(norm) vec | Float32 256^3 | 15.394 ms | 15.401 ms | 15.309 ms | 15.369 ms | — | — | — | — | — | — | 2.136 ms | — |
| maximum(norm) vec | Float32 64^3 | 225.513 μs | 225.213 μs | 225.051 μs | 224.996 μs | — | — | — | — | — | — | 350.398 μs | — |
| maximum(norm) vec | Float64 128^3 | 5.352 ms | 5.353 ms | 5.343 ms | 5.337 ms | — | — | — | — | — | — | 799.036 μs | — |
| maximum(norm) vec | Float64 256^3 | 43.808 ms | 43.733 ms | 43.304 ms | 43.411 ms | — | — | — | — | — | — | 4.228 ms | — |
| maximum(norm) vec | Float64 64^3 | 651.504 μs | 652.016 μs | 651.976 μs | 651.660 μs | — | — | — | — | — | — | 383.337 μs | — |
| mean spectral vec | Float32 128^3 | 70.324 ns | 70.922 ns | 70.948 ns | 71.788 ns | — | — | — | — | — | — | 308.514 μs | — |
| mean spectral vec | Float32 256^3 | 70.641 ns | 71.118 ns | 71.496 ns | 71.424 ns | — | — | — | — | — | — | 170.904 μs | — |
| mean spectral vec | Float32 64^3 | 70.581 ns | 70.389 ns | 70.261 ns | 71.427 ns | — | — | — | — | — | — | 315.433 μs | — |
| mean spectral vec | Float64 128^3 | 74.241 ns | 73.428 ns | 73.146 ns | 73.693 ns | — | — | — | — | — | — | 295.537 μs | — |
| mean spectral vec | Float64 256^3 | 74.676 ns | 74.353 ns | 78.820 ns | 73.872 ns | — | — | — | — | — | — | 295.185 μs | — |
| mean spectral vec | Float64 64^3 | 72.442 ns | 72.592 ns | 72.310 ns | 72.552 ns | — | — | — | — | — | — | 242.478 μs | — |
| mean vector | Float32 128^3 | 533.311 μs | 537.045 μs | 531.223 μs | 523.171 μs | 198.752 μs | 198.392 μs | 196.192 μs | 204.152 μs | 633.756 μs | 4.808 ms | 940.896 μs | 285.774 μs |
| mean vector | Float32 256^3 | 7.519 ms | 7.467 ms | 7.203 ms | 7.407 ms | 3.191 ms | 3.117 ms | 3.101 ms | 3.114 ms | — | 16.657 ms | 5.236 ms | 1.325 ms |
| mean vector | Float32 64^3 | 42.235 μs | 41.908 μs | 42.298 μs | 45.238 μs | 24.680 μs | 25.091 μs | 24.970 μs | 25.151 μs | 162.362 μs | 1.846 ms | 403.682 μs | 149.463 μs |
| mean vector | Float64 128^3 | 1.585 ms | 1.570 ms | 1.650 ms | 1.602 ms | 402.614 μs | 402.165 μs | 391.374 μs | 402.254 μs | 657.486 μs | 5.195 ms | 1.043 ms | 337.415 μs |
| mean vector | Float64 256^3 | 15.115 ms | 14.689 ms | 15.052 ms | 15.146 ms | 7.458 ms | 7.318 ms | 7.744 ms | 7.896 ms | — | 17.799 ms | 6.222 ms | 1.477 ms |
| mean vector | Float64 64^3 | 82.340 μs | 82.596 μs | 82.762 μs | 82.817 μs | 46.070 μs | 46.080 μs | 45.870 μs | 45.630 μs | 156.311 μs | 1.913 ms | 397.329 μs | 177.151 μs |
| mean(det) tensor | Float32 128^3 | 2.470 ms | 2.452 ms | 2.492 ms | 2.479 ms | — | — | — | — | — | — | 606.174 μs | — |
| mean(det) tensor | Float32 256^3 | 24.879 ms | 24.599 ms | 24.749 ms | 25.095 ms | — | — | — | — | — | — | 2.755 ms | — |
| mean(det) tensor | Float32 64^3 | 101.867 μs | 101.918 μs | 101.133 μs | 102.115 μs | — | — | — | — | — | — | 369.239 μs | — |
| mean(det) tensor | Float64 128^3 | 5.413 ms | 5.411 ms | 5.319 ms | 5.416 ms | — | — | — | — | — | — | 780.511 μs | — |
| mean(det) tensor | Float64 256^3 | 48.133 ms | 49.618 ms | 49.772 ms | 48.437 ms | — | — | — | — | — | — | 4.115 ms | — |
| mean(det) tensor | Float64 64^3 | 229.834 μs | 226.271 μs | 229.621 μs | 229.020 μs | — | — | — | — | — | — | 385.327 μs | — |
| mean(norm) vec | Float32 128^3 | 1.598 ms | 1.601 ms | 1.596 ms | 1.594 ms | — | — | — | — | — | — | 532.216 μs | — |
| mean(norm) vec | Float32 256^3 | 13.189 ms | 13.166 ms | 13.200 ms | 13.130 ms | — | — | — | — | — | — | 2.087 ms | — |
| mean(norm) vec | Float32 64^3 | 193.056 μs | 192.968 μs | 192.997 μs | 192.960 μs | — | — | — | — | — | — | 357.547 μs | — |
| mean(norm) vec | Float64 128^3 | 5.284 ms | 5.284 ms | 5.275 ms | 5.175 ms | — | — | — | — | — | — | 719.008 μs | — |
| mean(norm) vec | Float64 256^3 | 43.072 ms | 43.303 ms | 42.917 ms | 42.675 ms | — | — | — | — | — | — | 3.609 ms | — |
| mean(norm) vec | Float64 64^3 | 644.449 μs | 645.469 μs | 644.414 μs | 632.472 μs | — | — | — | — | — | — | 378.522 μs | — |
| mean(tr) tensor | Float32 128^3 | 395.648 μs | 400.391 μs | 417.426 μs | 394.809 μs | — | — | — | — | — | — | 494.486 μs | — |
| mean(tr) tensor | Float32 256^3 | 6.788 ms | 6.819 ms | 6.766 ms | 6.775 ms | — | — | — | — | — | — | 1.921 ms | — |
| mean(tr) tensor | Float32 64^3 | 35.425 μs | 34.565 μs | 34.820 μs | 34.552 μs | — | — | — | — | — | — | 358.443 μs | — |
| mean(tr) tensor | Float64 128^3 | 1.330 ms | 1.320 ms | 1.339 ms | 1.327 ms | — | — | — | — | — | — | 582.415 μs | — |
| mean(tr) tensor | Float64 256^3 | 13.692 ms | 13.983 ms | 13.790 ms | 13.851 ms | — | — | — | — | — | — | 2.349 ms | — |
| mean(tr) tensor | Float64 64^3 | 70.185 μs | 68.289 μs | 67.845 μs | 67.982 μs | — | — | — | — | — | — | 310.224 μs | — |
| radial_correlation vec | Float32 128^3 | 41.163 ms | 40.545 ms | 36.544 ms | 38.080 ms | 37.197 ms | 36.366 ms | 31.984 ms | 30.101 ms | 5.783 ms | 42.875 ms | 1.617 ms | 884.603 μs |
| radial_correlation vec | Float32 256^3 | 623.422 ms | 481.016 ms | 348.134 ms | 293.562 ms | 844.433 ms | 652.732 ms | 441.887 ms | 365.896 ms | — | 185.439 ms | 9.481 ms | 8.460 ms |
| radial_correlation vec | Float32 64^3 | 4.612 ms | 6.396 ms | 6.164 ms | 6.363 ms | 3.698 ms | 4.391 ms | 4.522 ms | 4.226 ms | 1.010 ms | 19.917 ms | 677.607 μs | 327.657 μs |
| radial_correlation vec | Float64 128^3 | 83.653 ms | 71.915 ms | 56.215 ms | 41.289 ms | 83.282 ms | 67.958 ms | 52.373 ms | 44.456 ms | 9.025 ms | 52.060 ms | 45.597 ms | 2.426 ms |
| radial_correlation vec | Float64 256^3 | 753.759 ms | 602.903 ms | 417.684 ms | 378.734 ms | 677.263 ms | 571.430 ms | 435.232 ms | 400.035 ms | — | 219.151 ms | 136.364 ms | 17.473 ms |
| radial_correlation vec | Float64 64^3 | 5.844 ms | 6.195 ms | 5.976 ms | 5.827 ms | 4.595 ms | 4.942 ms | 4.633 ms | 4.620 ms | 1.413 ms | 21.203 ms | 23.962 ms | 480.753 μs |
| radial_spectrum vec | Float32 128^3 | 7.677 ms | 6.451 ms | 8.022 ms | 8.200 ms | 10.907 ms | 12.367 ms | 12.568 ms | 14.116 ms | 1.415 ms | 27.166 ms | 821.492 μs | 409.336 μs |
| radial_spectrum vec | Float32 256^3 | 61.645 ms | 48.585 ms | 48.479 ms | 42.703 ms | 101.479 ms | 107.468 ms | 102.588 ms | 105.434 ms | — | 96.772 ms | 2.468 ms | 1.721 ms |
| radial_spectrum vec | Float32 64^3 | 997.899 μs | 1.352 ms | 1.569 ms | 1.622 ms | 1.360 ms | 1.674 ms | 2.026 ms | 2.253 ms | 344.443 μs | 16.995 ms | 559.122 μs | 242.265 μs |
| radial_spectrum vec | Float64 128^3 | 7.692 ms | 6.821 ms | 6.225 ms | 5.635 ms | 12.866 ms | 14.281 ms | 14.676 ms | 14.843 ms | 1.515 ms | 29.791 ms | 27.835 ms | 610.840 μs |
| radial_spectrum vec | Float64 256^3 | 62.834 ms | 46.484 ms | 35.375 ms | 30.287 ms | 131.962 ms | 132.144 ms | 128.424 ms | 123.544 ms | — | 110.504 ms | 65.951 ms | 2.870 ms |
| radial_spectrum vec | Float64 64^3 | 1.001 ms | 753.724 μs | 1.048 ms | 1.108 ms | 1.505 ms | 1.839 ms | 2.247 ms | 2.256 ms | 380.613 μs | 16.740 ms | 14.885 ms | 299.442 μs |
| weighted_inner vec | Float32 128^3 | 12.769 ms | 12.743 ms | 12.759 ms | 12.619 ms | — | — | — | — | — | — | 781.489 μs | — |
| weighted_inner vec | Float32 256^3 | 101.316 ms | 101.074 ms | 100.560 ms | 100.045 ms | — | — | — | — | — | — | 3.664 ms | — |
| weighted_inner vec | Float32 64^3 | 1.629 ms | 1.627 ms | 1.633 ms | 1.608 ms | — | — | — | — | — | — | 435.151 μs | — |
| weighted_inner vec | Float64 128^3 | 13.922 ms | 13.913 ms | 13.689 ms | 13.752 ms | — | — | — | — | — | — | 895.200 μs | — |
| weighted_inner vec | Float64 256^3 | 112.122 ms | 112.189 ms | 110.242 ms | 112.406 ms | — | — | — | — | — | — | 4.606 ms | — |
| weighted_inner vec | Float64 64^3 | 1.724 ms | 1.725 ms | 1.713 ms | 1.727 ms | — | — | — | — | — | — | 427.115 μs | — |
| weighted_inner vec.vec | Float32 128^3 | 12.891 ms | 12.754 ms | 12.818 ms | 12.588 ms | — | — | — | — | — | — | 785.379 μs | — |
| weighted_inner vec.vec | Float32 256^3 | 101.369 ms | 100.652 ms | 101.275 ms | 100.337 ms | — | — | — | — | — | — | 3.636 ms | — |
| weighted_inner vec.vec | Float32 64^3 | 1.647 ms | 1.629 ms | 1.638 ms | 1.597 ms | — | — | — | — | — | — | 393.354 μs | — |
| weighted_inner vec.vec | Float64 128^3 | 14.416 ms | 14.195 ms | 14.171 ms | 13.930 ms | — | — | — | — | — | — | 887.918 μs | — |
| weighted_inner vec.vec | Float64 256^3 | 114.884 ms | 114.588 ms | 114.138 ms | 113.243 ms | — | — | — | — | — | — | 4.631 ms | — |
| weighted_inner vec.vec | Float64 64^3 | 1.772 ms | 1.731 ms | 1.723 ms | 1.733 ms | — | — | — | — | — | — | 443.334 μs | — |

