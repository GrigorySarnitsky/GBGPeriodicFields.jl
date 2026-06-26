# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-06-26 at commit `a8e0ee1` on Julia 1.12.6, host `Aiporetne`. Columns are the supplied runs; grids and element types are in the row labels. **CPU** = i7-12700K thread sweep 1/2/4/8 (host `Aiporetne`). **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, a *separate* office host, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling). The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh` plus the per-card archive in `benchmark/results/` (PERFORMANCE.md §6). ~10% jitter.

## fft

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX |
|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 4.921 ms | 3.266 ms | 2.366 ms | 2.083 ms | 788.067 μs | 2.421 ms | 1.139 ms |
| to_physical scalar | Float32 256^3 | 102.850 ms | 70.618 ms | 49.749 ms | 40.817 ms | — | 7.945 ms | 2.075 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | — | — | 13.948 ms |
| to_physical scalar | Float32 64^3 | 385.835 μs | 243.928 μs | 171.276 μs | 142.746 μs | 124.402 μs | 1.497 ms | 948.455 μs |
| to_physical scalar | Float64 128^3 | 7.785 ms | 5.724 ms | 4.692 ms | 4.297 ms | 1.905 ms | 3.750 ms | 1.733 ms |
| to_physical scalar | Float64 256^3 | 144.899 ms | 97.997 ms | 78.790 ms | 73.532 ms | — | 14.463 ms | 5.725 ms |
| to_physical scalar | Float64 64^3 | 686.286 μs | 406.592 μs | 287.333 μs | 255.369 μs | 331.873 μs | 1.784 ms | 1.041 ms |
| to_physical vector | Float32 128^3 | 14.722 ms | 11.309 ms | 7.793 ms | 7.322 ms | 2.507 ms | 4.595 ms | 1.504 ms |
| to_physical vector | Float32 256^3 | 347.369 ms | 257.868 ms | 161.804 ms | 136.210 ms | — | 14.844 ms | 5.663 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | — | — | 37.321 ms |
| to_physical vector | Float32 64^3 | 1.271 ms | 965.245 μs | 514.575 μs | 459.392 μs | 380.054 μs | 1.776 ms | 1.009 ms |
| to_physical vector | Float64 128^3 | 44.457 ms | 29.335 ms | 19.738 ms | 18.426 ms | 5.630 ms | 8.090 ms | 2.643 ms |
| to_physical vector | Float64 256^3 | 434.606 ms | 339.808 ms | 241.896 ms | 227.297 ms | — | 22.812 ms | 13.528 ms |
| to_physical vector | Float64 64^3 | 2.488 ms | 2.032 ms | 1.580 ms | 1.192 ms | 811.437 μs | 2.301 ms | 1.341 ms |
| to_spectral scalar | Float32 128^3 | 4.349 ms | 2.631 ms | 1.893 ms | 1.192 ms | 488.254 μs | 2.072 ms | 962.238 μs |
| to_spectral scalar | Float32 256^3 | 100.167 ms | 66.664 ms | 45.739 ms | 35.244 ms | — | 5.009 ms | 1.517 ms |
| to_spectral scalar | Float32 512^3 | — | — | — | — | — | — | 9.890 ms |
| to_spectral scalar | Float32 64^3 | 364.578 μs | 208.081 μs | 128.108 μs | 105.585 μs | 89.181 μs | 1.538 ms | 932.562 μs |
| to_spectral scalar | Float64 128^3 | 7.199 ms | 4.917 ms | 4.092 ms | 3.382 ms | 1.501 ms | 3.125 ms | 1.406 ms |
| to_spectral scalar | Float64 256^3 | 163.090 ms | 103.339 ms | 74.590 ms | 64.087 ms | — | 12.871 ms | 4.868 ms |
| to_spectral scalar | Float64 64^3 | 641.074 μs | 352.984 μs | 219.246 μs | 194.986 μs | 265.683 μs | 1.745 ms | 1.142 ms |
| to_spectral vector | Float32 128^3 | 13.414 ms | 9.753 ms | 6.668 ms | 5.805 ms | 1.355 ms | 3.183 ms | 1.098 ms |
| to_spectral vector | Float32 256^3 | 337.029 ms | 248.543 ms | 147.222 ms | 121.232 ms | — | 11.819 ms | 3.421 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | — | — | 20.275 ms |
| to_spectral vector | Float32 64^3 | 1.193 ms | 848.736 μs | 436.803 μs | 390.848 μs | 230.522 μs | 1.566 ms | 916.771 μs |
| to_spectral vector | Float64 128^3 | 41.796 ms | 27.006 ms | 15.960 ms | 15.034 ms | 4.144 ms | 6.538 ms | 2.330 ms |
| to_spectral vector | Float64 256^3 | 495.582 ms | 364.743 ms | 231.935 ms | 204.674 ms | — | 20.041 ms | 12.003 ms |
| to_spectral vector | Float64 64^3 | 2.235 ms | 1.825 ms | 1.007 ms | 779.658 μs | 596.836 μs | 2.151 ms | 1.182 ms |

## algebra

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX |
|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 396.368 μs | 3.594 ms | 1.802 ms | 944.513 μs | 351.303 μs | 1.943 ms | 1.042 ms |
| add! scalar | Float32 256^3 | 8.111 ms | 28.784 ms | 14.394 ms | 7.585 ms | — | 6.480 ms | 1.676 ms |
| add! scalar | Float32 512^3 | — | — | — | — | — | — | 6.590 ms |
| add! scalar | Float32 64^3 | 42.150 μs | 454.807 μs | 229.108 μs | 121.780 μs | 85.391 μs | 1.599 ms | 912.192 μs |
| add! scalar | Float64 128^3 | 1.465 ms | 3.696 ms | 1.828 ms | 1.078 ms | 354.693 μs | 2.024 ms | 953.084 μs |
| add! scalar | Float64 256^3 | 16.851 ms | 29.062 ms | 15.725 ms | 14.509 ms | — | 5.550 ms | 1.794 ms |
| add! scalar | Float64 64^3 | 83.639 μs | 452.884 μs | 232.543 μs | 122.106 μs | 83.741 μs | 1.494 ms | 839.642 μs |
| cross! | Float32 128^3 | 4.497 ms | 16.605 ms | 8.419 ms | 4.406 ms | 1.223 ms | 3.445 ms | 1.483 ms |
| cross! | Float32 256^3 | 42.066 ms | 134.071 ms | 67.606 ms | 36.754 ms | — | 14.690 ms | 3.962 ms |
| cross! | Float32 512^3 | — | — | — | — | — | — | 17.511 ms |
| cross! | Float32 64^3 | 421.360 μs | 2.046 ms | 1.029 ms | 542.913 μs | 219.582 μs | 1.665 ms | 995.230 μs |
| cross! | Float64 128^3 | 9.486 ms | 16.626 ms | 8.415 ms | 7.174 ms | 1.263 ms | 2.603 ms | 1.495 ms |
| cross! | Float64 256^3 | 78.267 ms | 131.772 ms | 76.338 ms | 67.731 ms | — | 15.625 ms | 4.811 ms |
| cross! | Float64 64^3 | 510.928 μs | 1.972 ms | 1.016 ms | 531.231 μs | 216.592 μs | 1.846 ms | 909.181 μs |
| dot! vec.vec | Float32 128^3 | 2.847 ms | 6.786 ms | 3.419 ms | 1.782 ms | 538.855 μs | 2.430 ms | 1.167 ms |
| dot! vec.vec | Float32 256^3 | 24.593 ms | 54.301 ms | 27.539 ms | 15.266 ms | — | 9.651 ms | 2.357 ms |
| dot! vec.vec | Float32 512^3 | — | — | — | — | — | — | 10.351 ms |
| dot! vec.vec | Float32 64^3 | 352.398 μs | 834.785 μs | 419.919 μs | 221.656 μs | 112.901 μs | 1.663 ms | 1.069 ms |
| dot! vec.vec | Float64 128^3 | 4.386 ms | 6.952 ms | 3.608 ms | 2.986 ms | 618.906 μs | 2.505 ms | 1.199 ms |
| dot! vec.vec | Float64 256^3 | 38.331 ms | 54.907 ms | 33.006 ms | 29.908 ms | — | 9.784 ms | 2.725 ms |
| dot! vec.vec | Float64 64^3 | 338.200 μs | 830.601 μs | 423.852 μs | 223.056 μs | 127.611 μs | 1.656 ms | 959.688 μs |
| mul! tensor.vec | Float32 128^3 | 8.603 ms | 21.066 ms | 10.566 ms | 5.548 ms | 1.525 ms | 4.295 ms | 1.687 ms |
| mul! tensor.vec | Float32 256^3 | 75.840 ms | 171.026 ms | 85.807 ms | 48.378 ms | — | 16.892 ms | 4.761 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | — | — | 20.125 ms |
| mul! tensor.vec | Float32 64^3 | 986.212 μs | 2.561 ms | 1.295 ms | 679.527 μs | 255.702 μs | 1.882 ms | 1.025 ms |
| mul! tensor.vec | Float64 128^3 | 13.759 ms | 21.334 ms | 11.212 ms | 10.648 ms | 1.748 ms | 4.757 ms | 1.804 ms |
| mul! tensor.vec | Float64 256^3 | 113.321 ms | 170.205 ms | 101.438 ms | 91.008 ms | — | 17.818 ms | 6.290 ms |
| mul! tensor.vec | Float64 64^3 | 1.085 ms | 2.542 ms | 1.323 ms | 699.683 μs | 280.183 μs | 1.951 ms | 974.268 μs |
| norm! vec | Float32 128^3 | 741.427 μs | 4.925 ms | 2.464 ms | 1.290 ms | 411.304 μs | 2.110 ms | 1.064 ms |
| norm! vec | Float32 256^3 | 10.265 ms | 39.876 ms | 19.764 ms | 10.124 ms | — | 7.304 ms | 1.848 ms |
| norm! vec | Float32 512^3 | — | — | — | — | — | — | 7.897 ms |
| norm! vec | Float32 64^3 | 53.553 μs | 611.901 μs | 304.437 μs | 160.472 μs | 100.251 μs | 1.526 ms | 875.177 μs |
| norm! vec | Float64 128^3 | 2.098 ms | 5.239 ms | 2.517 ms | 1.612 ms | 463.344 μs | 1.434 ms | 1.291 ms |
| norm! vec | Float64 256^3 | 21.082 ms | 40.692 ms | 21.174 ms | 18.922 ms | — | 9.850 ms | 3.297 ms |
| norm! vec | Float64 64^3 | 157.691 μs | 625.248 μs | 329.507 μs | 166.731 μs | 101.231 μs | 1.681 ms | 925.186 μs |

## operators

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX |
|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.222 ms | 8.904 ms | 4.490 ms | 2.380 ms | 697.807 μs | 2.544 ms | 1.145 ms |
| curl! vec->vec | Float32 256^3 | 41.269 ms | 70.866 ms | 36.403 ms | 23.732 ms | — | 10.865 ms | 2.659 ms |
| curl! vec->vec | Float32 512^3 | — | — | — | — | — | — | 12.257 ms |
| curl! vec->vec | Float32 64^3 | 631.026 μs | 1.146 ms | 588.208 μs | 309.261 μs | 182.902 μs | 1.646 ms | 851.036 μs |
| curl! vec->vec | Float64 128^3 | 6.135 ms | 9.056 ms | 5.054 ms | 3.896 ms | 824.588 μs | 3.153 ms | 1.435 ms |
| curl! vec->vec | Float64 256^3 | 54.434 ms | 72.029 ms | 47.645 ms | 36.942 ms | — | 13.647 ms | 3.944 ms |
| curl! vec->vec | Float64 64^3 | 513.755 μs | 1.134 ms | 571.142 μs | 305.670 μs | 186.242 μs | 1.786 ms | 921.512 μs |
| divergence! vec->scalar | Float32 128^3 | 3.471 ms | 3.644 ms | 1.831 ms | 971.105 μs | 326.353 μs | 1.957 ms | 979.982 μs |
| divergence! vec->scalar | Float32 256^3 | 27.517 ms | 29.274 ms | 14.822 ms | 9.284 ms | — | 5.523 ms | 1.627 ms |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | — | — | 6.316 ms |
| divergence! vec->scalar | Float32 64^3 | 417.381 μs | 464.333 μs | 236.520 μs | 126.381 μs | 93.900 μs | 1.537 ms | 932.691 μs |
| divergence! vec->scalar | Float64 128^3 | 3.611 ms | 3.877 ms | 1.985 ms | 1.563 ms | 407.644 μs | 2.306 ms | 1.064 ms |
| divergence! vec->scalar | Float64 256^3 | 31.088 ms | 30.553 ms | 20.015 ms | 18.656 ms | — | 7.090 ms | 2.228 ms |
| divergence! vec->scalar | Float64 64^3 | 422.384 μs | 459.442 μs | 232.773 μs | 125.385 μs | 103.111 μs | 344.869 μs | 841.784 μs |
| gradient! scalar->vec | Float32 128^3 | 3.756 ms | 6.183 ms | 3.111 ms | 1.650 ms | 560.525 μs | 2.377 ms | 504.117 μs |
| gradient! scalar->vec | Float32 256^3 | 30.847 ms | 49.059 ms | 24.635 ms | 15.903 ms | — | 7.929 ms | 2.249 ms |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | — | — | 9.912 ms |
| gradient! scalar->vec | Float32 64^3 | 472.399 μs | 795.708 μs | 403.847 μs | 217.811 μs | 133.261 μs | 1.681 ms | 1.029 ms |
| gradient! scalar->vec | Float64 128^3 | 3.880 ms | 6.305 ms | 3.275 ms | 2.224 ms | 605.225 μs | 2.717 ms | 1.251 ms |
| gradient! scalar->vec | Float64 256^3 | 39.229 ms | 49.150 ms | 33.255 ms | 26.071 ms | — | 10.338 ms | 3.302 ms |
| gradient! scalar->vec | Float64 64^3 | 365.183 μs | 787.674 μs | 405.788 μs | 217.564 μs | 153.172 μs | 1.872 ms | 941.767 μs |
| helmholtz! vec->vec | Float32 128^3 | 23.626 ms | 19.664 ms | 9.986 ms | 5.252 ms | 1.480 ms | 4.174 ms | 1.508 ms |
| helmholtz! vec->vec | Float32 256^3 | 186.391 ms | 157.101 ms | 80.077 ms | 42.299 ms | — | 16.637 ms | 4.679 ms |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | — | — | 21.939 ms |
| helmholtz! vec->vec | Float32 64^3 | 3.022 ms | 2.502 ms | 1.303 ms | 663.349 μs | 286.333 μs | 1.935 ms | 1.084 ms |
| helmholtz! vec->vec | Float64 128^3 | 23.886 ms | 20.636 ms | 10.123 ms | 6.000 ms | 1.802 ms | 5.921 ms | 2.221 ms |
| helmholtz! vec->vec | Float64 256^3 | 195.606 ms | 164.003 ms | 83.326 ms | 59.623 ms | — | 18.240 ms | 8.808 ms |
| helmholtz! vec->vec | Float64 64^3 | 3.007 ms | 2.566 ms | 1.325 ms | 692.565 μs | 342.613 μs | 2.260 ms | 1.087 ms |
| laplacian! scalar | Float32 128^3 | 2.009 ms | 2.708 ms | 1.370 ms | 718.403 μs | 265.103 μs | 1.910 ms | 969.421 μs |
| laplacian! scalar | Float32 256^3 | 16.237 ms | 21.343 ms | 10.746 ms | 5.669 ms | — | 5.490 ms | 1.626 ms |
| laplacian! scalar | Float32 512^3 | — | — | — | — | — | — | 5.065 ms |
| laplacian! scalar | Float32 64^3 | 250.491 μs | 339.201 μs | 178.372 μs | 92.927 μs | 83.431 μs | 1.563 ms | 981.262 μs |
| laplacian! scalar | Float64 128^3 | 2.062 ms | 2.762 ms | 1.385 ms | 728.402 μs | 278.082 μs | 1.957 ms | 1.103 ms |
| laplacian! scalar | Float64 256^3 | 16.912 ms | 21.940 ms | 11.947 ms | 9.586 ms | — | 4.740 ms | 1.921 ms |
| laplacian! scalar | Float64 64^3 | 253.707 μs | 346.302 μs | 176.959 μs | 94.801 μs | 84.420 μs | 1.586 ms | 866.890 μs |

## convolution

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX |
|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.810 ms | 2.204 ms | 1.110 ms | 582.818 μs | 296.642 μs | 1.855 ms | 953.931 μs |
| assignment_window | Float32 256^3 | 14.400 ms | 23.922 ms | 12.142 ms | 6.464 ms | — | 3.952 ms | 1.588 ms |
| assignment_window | Float32 512^3 | — | — | — | — | — | — | 4.436 ms |
| assignment_window | Float32 64^3 | 223.795 μs | 283.827 μs | 145.040 μs | 78.345 μs | 138.651 μs | 1.640 ms | 1.025 ms |
| assignment_window | Float64 128^3 | 1.872 ms | 2.195 ms | 1.111 ms | 706.984 μs | 306.863 μs | 1.901 ms | 1.077 ms |
| assignment_window | Float64 256^3 | 39.420 ms | 30.461 ms | 15.876 ms | 8.881 ms | — | 4.237 ms | 1.568 ms |
| assignment_window | Float64 64^3 | 230.089 μs | 279.351 μs | 145.224 μs | 82.091 μs | 141.232 μs | 1.542 ms | 924.819 μs |
| convolve! scalar | Float32 128^3 | 1.608 ms | 2.068 ms | 1.040 ms | 545.680 μs | 220.032 μs | 1.755 ms | 982.320 μs |
| convolve! scalar | Float32 256^3 | 13.236 ms | 16.384 ms | 8.384 ms | 6.864 ms | — | 3.659 ms | 1.382 ms |
| convolve! scalar | Float32 512^3 | — | — | — | — | — | — | 3.926 ms |
| convolve! scalar | Float32 64^3 | 197.514 μs | 265.213 μs | 134.578 μs | 71.836 μs | 78.951 μs | 1.480 ms | 930.180 μs |
| convolve! scalar | Float64 128^3 | 1.808 ms | 2.097 ms | 1.260 ms | 927.499 μs | 302.553 μs | 1.784 ms | 1.005 ms |
| convolve! scalar | Float64 256^3 | 18.188 ms | 17.350 ms | 12.807 ms | 11.248 ms | — | 4.442 ms | 1.746 ms |
| convolve! scalar | Float64 64^3 | 177.223 μs | 259.129 μs | 132.195 μs | 71.148 μs | 78.591 μs | 1.618 ms | 870.951 μs |
| convolve! vector | Float32 128^3 | 5.868 ms | 8.948 ms | 4.496 ms | 2.443 ms | 731.727 μs | 2.557 ms | 1.190 ms |
| convolve! vector | Float32 256^3 | 47.415 ms | 70.960 ms | 36.530 ms | 22.250 ms | — | 10.821 ms | 2.662 ms |
| convolve! vector | Float32 512^3 | — | — | — | — | — | — | 12.278 ms |
| convolve! vector | Float32 64^3 | 719.951 μs | 1.139 ms | 570.990 μs | 299.368 μs | 161.751 μs | 1.595 ms | 1.020 ms |
| convolve! vector | Float64 128^3 | 6.760 ms | 9.149 ms | 4.928 ms | 3.849 ms | 792.657 μs | 2.910 ms | 1.303 ms |
| convolve! vector | Float64 256^3 | 57.390 ms | 73.087 ms | 45.061 ms | 38.599 ms | — | 12.297 ms | 3.519 ms |
| convolve! vector | Float64 64^3 | 731.277 μs | 1.149 ms | 574.943 μs | 303.198 μs | 167.451 μs | 1.655 ms | 946.137 μs |
| spectral_band | Float32 128^3 | 4.132 ms | 3.349 ms | 1.679 ms | 899.854 μs | 334.154 μs | 2.050 ms | 992.738 μs |
| spectral_band | Float32 256^3 | 32.212 ms | 32.960 ms | 16.703 ms | 8.836 ms | — | 6.344 ms | 1.531 ms |
| spectral_band | Float32 512^3 | — | — | — | — | — | — | 6.165 ms |
| spectral_band | Float32 64^3 | 515.248 μs | 427.300 μs | 216.287 μs | 116.124 μs | 106.071 μs | 1.537 ms | 896.651 μs |
| spectral_band | Float64 128^3 | 4.181 ms | 3.384 ms | 1.703 ms | 945.074 μs | 361.113 μs | 2.105 ms | 1.063 ms |
| spectral_band | Float64 256^3 | 56.634 ms | 39.813 ms | 20.354 ms | 11.152 ms | — | 5.611 ms | 2.131 ms |
| spectral_band | Float64 64^3 | 523.445 μs | 432.790 μs | 219.044 μs | 122.680 μs | 110.411 μs | 1.651 ms | 903.967 μs |
| spectral_cutoff | Float32 128^3 | 4.069 ms | 3.346 ms | 1.681 ms | 880.161 μs | 331.623 μs | 2.046 ms | 1.058 ms |
| spectral_cutoff | Float32 256^3 | 32.085 ms | 32.952 ms | 16.679 ms | 8.807 ms | — | 5.403 ms | 1.441 ms |
| spectral_cutoff | Float32 512^3 | — | — | — | — | — | — | 6.128 ms |
| spectral_cutoff | Float32 64^3 | 513.846 μs | 427.338 μs | 216.272 μs | 116.014 μs | 108.881 μs | 1.625 ms | 900.307 μs |
| spectral_cutoff | Float64 128^3 | 4.215 ms | 3.389 ms | 1.704 ms | 994.427 μs | 351.793 μs | 2.120 ms | 1.069 ms |
| spectral_cutoff | Float64 256^3 | 56.642 ms | 39.837 ms | 20.334 ms | 11.093 ms | — | 5.621 ms | 1.887 ms |
| spectral_cutoff | Float64 64^3 | 524.238 μs | 432.883 μs | 218.867 μs | 122.403 μs | 117.711 μs | 1.647 ms | 927.124 μs |
| squared_wavenumber_field | Float32 128^3 | 1.795 ms | 2.192 ms | 1.102 ms | 577.195 μs | 262.463 μs | 1.824 ms | 941.890 μs |
| squared_wavenumber_field | Float32 256^3 | 14.154 ms | 23.931 ms | 12.130 ms | 6.450 ms | — | 3.812 ms | 1.392 ms |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | — | — | 4.602 ms |
| squared_wavenumber_field | Float32 64^3 | 224.872 μs | 281.132 μs | 142.787 μs | 77.050 μs | 91.321 μs | 1.517 ms | 918.984 μs |
| squared_wavenumber_field | Float64 128^3 | 1.864 ms | 2.175 ms | 1.099 ms | 656.365 μs | 264.163 μs | 1.805 ms | 1.001 ms |
| squared_wavenumber_field | Float64 256^3 | 39.317 ms | 30.276 ms | 15.696 ms | 8.802 ms | — | 4.151 ms | 1.657 ms |
| squared_wavenumber_field | Float64 64^3 | 226.996 μs | 281.210 μs | 143.430 μs | 78.173 μs | 88.931 μs | 1.612 ms | 336.869 μs |

## transfer

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX |
|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.443 ms | 13.693 ms | 7.285 ms | 4.377 ms | 2.280 ms | 4.864 ms | 1.408 ms |
| anterpolate! CatmullRom | Float32 256^3 | 391.098 ms | 201.712 ms | 108.413 ms | 65.415 ms | — | 17.932 ms | 3.843 ms |
| anterpolate! CatmullRom | Float32 64^3 | 3.164 ms | 1.837 ms | 1.202 ms | 855.568 μs | 116.972 μs | 2.057 ms | 1.003 ms |
| anterpolate! CatmullRom | Float64 128^3 | 29.485 ms | 14.941 ms | 7.534 ms | 4.631 ms | 2.691 ms | 4.862 ms | 1.521 ms |
| anterpolate! CatmullRom | Float64 256^3 | 498.333 ms | 264.731 ms | 150.178 ms | 102.950 ms | — | 19.810 ms | 4.764 ms |
| anterpolate! CatmullRom | Float64 64^3 | 3.324 ms | 1.872 ms | 1.251 ms | 889.978 μs | 185.312 μs | 2.004 ms | 1.243 ms |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 197.320 ms | 100.304 ms | 51.325 ms | 28.559 ms | 12.241 ms | 15.478 ms | 3.965 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.252 s | 1.157 s | 674.315 ms | 485.072 ms | — | 48.567 ms | 17.491 ms |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.824 ms | 13.119 ms | 8.180 ms | 5.591 ms | 486.825 μs | 5.959 ms | 2.138 ms |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 209.012 ms | 105.711 ms | 52.680 ms | 29.833 ms | 13.808 ms | 16.564 ms | 5.239 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.633 s | 1.408 s | 865.827 ms | 620.439 ms | — | 66.043 ms | 28.558 ms |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.350 ms | 13.250 ms | 8.263 ms | 5.729 ms | 825.268 μs | 5.503 ms | 2.565 ms |
| anterpolate! NUFFT | Float32 128^3 | 422.604 ms | 237.509 ms | 149.832 ms | 102.525 ms | 20.177 ms | 18.762 ms | 5.434 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.338 s | 2.420 s | 1.492 s | 1.113 s | — | 120.799 ms | 33.673 ms |
| anterpolate! NUFFT | Float32 64^3 | 31.694 ms | 18.004 ms | 11.336 ms | 8.262 ms | 1.989 ms | 6.296 ms | 2.192 ms |
| anterpolate! NUFFT | Float64 128^3 | 539.909 ms | 321.231 ms | 222.110 ms | 182.048 ms | 30.358 ms | 22.503 ms | 9.608 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.077 s | 2.955 s | 1.914 s | 1.538 s | — | 160.735 ms | 56.224 ms |
| anterpolate! NUFFT | Float64 64^3 | 37.402 ms | 21.348 ms | 14.651 ms | 10.913 ms | 3.892 ms | 8.203 ms | 3.136 ms |
| anterpolate! trilinear | Float32 128^3 | 4.559 ms | 2.283 ms | 1.311 ms | 886.814 μs | 460.884 μs | 2.018 ms | 343.875 μs |
| anterpolate! trilinear | Float32 256^3 | 79.138 ms | 44.216 ms | 26.154 ms | 18.726 ms | — | 6.631 ms | 1.524 ms |
| anterpolate! trilinear | Float32 64^3 | 482.247 μs | 321.325 μs | 219.915 μs | 161.879 μs | 70.080 μs | 1.565 ms | 945.872 μs |
| anterpolate! trilinear | Float64 128^3 | 5.395 ms | 2.763 ms | 1.553 ms | 1.092 ms | 596.666 μs | 1.980 ms | 937.331 μs |
| anterpolate! trilinear | Float64 256^3 | 89.885 ms | 51.919 ms | 34.343 ms | 27.261 ms | — | 6.838 ms | 1.703 ms |
| anterpolate! trilinear | Float64 64^3 | 513.175 μs | 338.641 μs | 240.095 μs | 191.633 μs | 83.721 μs | 1.554 ms | 995.761 μs |
| interpolate! CatmullRom | Float32 128^3 | 11.402 ms | 5.828 ms | 2.938 ms | 1.645 ms | 972.889 μs | 3.140 ms | 1.228 ms |
| interpolate! CatmullRom | Float32 256^3 | 264.098 ms | 138.857 ms | 74.798 ms | 45.183 ms | — | 14.577 ms | 2.749 ms |
| interpolate! CatmullRom | Float32 64^3 | 1.304 ms | 708.859 μs | 426.814 μs | 298.310 μs | 101.321 μs | 1.724 ms | 1.093 ms |
| interpolate! CatmullRom | Float64 128^3 | 13.451 ms | 7.284 ms | 3.432 ms | 1.935 ms | 1.411 ms | 2.789 ms | 1.293 ms |
| interpolate! CatmullRom | Float64 256^3 | 300.615 ms | 159.415 ms | 91.360 ms | 60.958 ms | — | 12.939 ms | 2.886 ms |
| interpolate! CatmullRom | Float64 64^3 | 1.363 ms | 737.024 μs | 456.609 μs | 314.094 μs | 166.201 μs | 1.759 ms | 978.998 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.561 ms | 37.299 ms | 18.846 ms | 10.350 ms | 5.370 ms | 14.027 ms | 2.652 ms |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.392 s | 767.141 ms | 501.836 ms | 326.527 ms | — | 30.216 ms | 11.934 ms |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.710 ms | 4.707 ms | 2.832 ms | 1.949 ms | 688.416 μs | 3.166 ms | 1.693 ms |
| interpolate! Lalescu(3,3) | Float64 128^3 | 85.097 ms | 45.114 ms | 21.552 ms | 12.012 ms | 8.105 ms | 9.517 ms | 2.981 ms |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.844 s | 1.015 s | 671.894 ms | 434.462 ms | — | 28.103 ms | 11.246 ms |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.956 ms | 4.824 ms | 2.937 ms | 2.007 ms | 911.428 μs | 3.595 ms | 2.190 ms |
| interpolate! NUFFT | Float32 128^3 | 323.801 ms | 193.680 ms | 134.181 ms | 101.856 ms | 12.723 ms | 16.422 ms | 4.626 ms |
| interpolate! NUFFT | Float32 256^3 | 3.612 s | 2.076 s | 1.373 s | 1.002 s | — | 72.243 ms | 26.966 ms |
| interpolate! NUFFT | Float32 64^3 | 16.659 ms | 10.223 ms | 6.931 ms | 5.351 ms | 1.847 ms | 4.302 ms | 2.045 ms |
| interpolate! NUFFT | Float64 128^3 | 430.679 ms | 265.673 ms | 195.053 ms | 162.741 ms | 25.361 ms | 18.237 ms | 8.978 ms |
| interpolate! NUFFT | Float64 256^3 | 3.916 s | 2.356 s | 1.691 s | 1.358 s | — | 118.516 ms | 42.530 ms |
| interpolate! NUFFT | Float64 64^3 | 22.224 ms | 14.154 ms | 10.924 ms | 8.988 ms | 3.417 ms | 6.116 ms | 2.877 ms |
| interpolate! trilinear | Float32 128^3 | 1.978 ms | 1.020 ms | 518.153 μs | 291.856 μs | 255.582 μs | 1.719 ms | 943.961 μs |
| interpolate! trilinear | Float32 256^3 | 51.992 ms | 28.098 ms | 14.630 ms | 8.908 ms | — | 3.594 ms | 1.177 ms |
| interpolate! trilinear | Float32 64^3 | 224.576 μs | 126.441 μs | 77.316 μs | 56.387 μs | 65.160 μs | 1.448 ms | 921.845 μs |
| interpolate! trilinear | Float64 128^3 | 2.498 ms | 1.372 ms | 645.168 μs | 356.800 μs | 325.503 μs | 1.772 ms | 966.201 μs |
| interpolate! trilinear | Float64 256^3 | 57.959 ms | 32.808 ms | 20.478 ms | 13.674 ms | — | 4.014 ms | 1.565 ms |
| interpolate! trilinear | Float64 64^3 | 238.528 μs | 133.571 μs | 82.063 μs | 57.471 μs | 65.930 μs | 1.530 ms | 957.599 μs |

## reductions

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX |
|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 14.995 ms | 19.839 ms | 19.405 ms | 19.518 ms | 2.099 ms | 27.761 ms | 5.016 ms |
| co-spectrum vec.vec | Float32 256^3 | 149.676 ms | 164.249 ms | 165.915 ms | 153.666 ms | — | 97.666 ms | 21.554 ms |
| co-spectrum vec.vec | Float32 64^3 | 1.621 ms | 2.739 ms | 2.859 ms | 3.147 ms | 491.824 μs | 17.761 ms | 1.880 ms |
| co-spectrum vec.vec | Float64 128^3 | 19.035 ms | 20.856 ms | 21.404 ms | 21.689 ms | 2.194 ms | 29.708 ms | 34.131 ms |
| co-spectrum vec.vec | Float64 256^3 | 209.717 ms | 223.349 ms | 214.545 ms | 207.393 ms | — | 109.563 ms | 88.155 ms |
| co-spectrum vec.vec | Float64 64^3 | 2.025 ms | 2.966 ms | 2.855 ms | 3.039 ms | 482.135 μs | 16.075 ms | 19.060 ms |
| cross-correlation vec.vec | Float32 128^3 | 44.866 ms | 50.572 ms | 44.169 ms | 42.979 ms | 5.891 ms | 43.640 ms | 9.003 ms |
| cross-correlation vec.vec | Float32 256^3 | 683.208 ms | 623.062 ms | 460.970 ms | 405.811 ms | — | 186.915 ms | 35.688 ms |
| cross-correlation vec.vec | Float32 64^3 | 5.044 ms | 7.246 ms | 6.505 ms | 6.754 ms | 1.025 ms | 20.682 ms | 2.534 ms |
| cross-correlation vec.vec | Float64 128^3 | 95.130 ms | 71.859 ms | 78.447 ms | 97.665 ms | 9.144 ms | 52.055 ms | 58.087 ms |
| cross-correlation vec.vec | Float64 256^3 | 888.066 ms | 763.266 ms | 615.351 ms | 564.273 ms | — | 217.471 ms | 185.570 ms |
| cross-correlation vec.vec | Float64 64^3 | 6.637 ms | 7.735 ms | 7.329 ms | 6.933 ms | 1.557 ms | 20.881 ms | 25.350 ms |
| inner spectral | Float32 128^3 | 1.506 ms | 1.570 ms | 1.526 ms | 1.563 ms | 669.926 μs | 2.049 ms | 1.131 ms |
| inner spectral | Float32 256^3 | 15.524 ms | 15.859 ms | 15.485 ms | 16.012 ms | — | 3.999 ms | 1.639 ms |
| inner spectral | Float32 64^3 | 144.384 μs | 145.246 μs | 145.375 μs | 145.038 μs | 275.972 μs | 1.780 ms | 1.099 ms |
| inner spectral | Float64 128^3 | 2.966 ms | 2.958 ms | 2.964 ms | 3.001 ms | 811.337 μs | 2.410 ms | 1.307 ms |
| inner spectral | Float64 256^3 | 26.806 ms | 27.189 ms | 26.812 ms | 26.766 ms | — | 7.953 ms | 2.867 ms |
| inner spectral | Float64 64^3 | 119.534 μs | 118.581 μs | 122.820 μs | 120.904 μs | 293.003 μs | 1.765 ms | 1.147 ms |
| inner vec.vec | Float32 128^3 | 1.173 ms | 1.221 ms | 1.179 ms | 1.188 ms | 308.353 μs | 1.623 ms | 747.598 μs |
| inner vec.vec | Float32 256^3 | 12.548 ms | 12.631 ms | 12.644 ms | 12.476 ms | — | 3.382 ms | 1.222 ms |
| inner vec.vec | Float32 64^3 | 65.932 μs | 65.900 μs | 64.680 μs | 64.856 μs | 98.731 μs | 1.278 ms | 783.174 μs |
| inner vec.vec | Float64 128^3 | 2.171 ms | 2.153 ms | 2.177 ms | 2.181 ms | 552.615 μs | 1.860 ms | 995.351 μs |
| inner vec.vec | Float64 256^3 | 22.243 ms | 22.218 ms | 22.224 ms | 22.229 ms | — | 5.634 ms | 2.055 ms |
| inner vec.vec | Float64 64^3 | 30.934 μs | 32.911 μs | 33.589 μs | 31.350 μs | 162.792 μs | 1.434 ms | 782.068 μs |
| integral scalar | Float32 128^3 | 109.471 μs | 109.285 μs | 108.682 μs | 107.502 μs | 228.932 μs | 1.318 ms | 1.133 ms |
| integral scalar | Float32 256^3 | 2.271 ms | 2.042 ms | 2.001 ms | 1.987 ms | — | 9.002 ms | 2.348 ms |
| integral scalar | Float32 64^3 | 10.747 μs | 11.150 μs | 10.913 μs | 10.116 μs | 95.301 μs | 1.534 ms | 881.866 μs |
| integral scalar | Float64 128^3 | 232.447 μs | 230.409 μs | 233.534 μs | 237.706 μs | 221.812 μs | 2.553 ms | 1.105 ms |
| integral scalar | Float64 256^3 | 4.456 ms | 4.453 ms | 4.899 ms | 4.536 ms | — | 10.817 ms | 2.588 ms |
| integral scalar | Float64 64^3 | 25.809 μs | 27.364 μs | 25.740 μs | 25.633 μs | 95.391 μs | 1.583 ms | 897.014 μs |
| l2norm vec | Float32 128^3 | 456.298 μs | 452.407 μs | 485.932 μs | 473.416 μs | 196.632 μs | 1.582 ms | 824.058 μs |
| l2norm vec | Float32 256^3 | 6.539 ms | 6.517 ms | 6.956 ms | 6.495 ms | — | 3.219 ms | 1.263 ms |
| l2norm vec | Float32 64^3 | 39.712 μs | 39.610 μs | 40.386 μs | 39.670 μs | 85.641 μs | 1.361 ms | 754.549 μs |
| l2norm vec | Float64 128^3 | 717.589 μs | 775.945 μs | 711.893 μs | 739.292 μs | 344.333 μs | 1.876 ms | 972.788 μs |
| l2norm vec | Float64 256^3 | 11.067 ms | 11.023 ms | 11.043 ms | 11.062 ms | — | 5.670 ms | 1.996 ms |
| l2norm vec | Float64 64^3 | 16.610 μs | 16.296 μs | 16.389 μs | 11.366 μs | 134.871 μs | 1.402 ms | 774.626 μs |
| lpnorm vec Inf | Float32 128^3 | 1.311 ms | 5.374 ms | 3.038 ms | 1.888 ms | 592.145 μs | 3.080 ms | 1.329 ms |
| lpnorm vec Inf | Float32 256^3 | 14.310 ms | 50.455 ms | 26.103 ms | 18.176 ms | — | 13.216 ms | 3.421 ms |
| lpnorm vec Inf | Float32 64^3 | 95.873 μs | 655.556 μs | 359.198 μs | 216.069 μs | 155.751 μs | 1.641 ms | 940.727 μs |
| lpnorm vec Inf | Float64 128^3 | 3.130 ms | 6.505 ms | 3.601 ms | 2.940 ms | 660.476 μs | 3.883 ms | 1.468 ms |
| lpnorm vec Inf | Float64 256^3 | 44.762 ms | 59.647 ms | 34.177 ms | 22.960 ms | — | 14.730 ms | 5.486 ms |
| lpnorm vec Inf | Float64 64^3 | 229.705 μs | 737.496 μs | 429.387 μs | 272.143 μs | 166.092 μs | 1.711 ms | 968.636 μs |
| maximum scalar | Float32 128^3 | 336.497 μs | 334.303 μs | 335.060 μs | 336.153 μs | 223.322 μs | 2.331 ms | 1.203 ms |
| maximum scalar | Float32 256^3 | 3.075 ms | 2.888 ms | 2.857 ms | 2.830 ms | — | 9.121 ms | 2.249 ms |
| maximum scalar | Float32 64^3 | 41.972 μs | 41.674 μs | 41.720 μs | 41.791 μs | 101.731 μs | 1.564 ms | 887.603 μs |
| maximum scalar | Float64 128^3 | 539.562 μs | 537.304 μs | 545.258 μs | 545.035 μs | 244.072 μs | 2.772 ms | 1.192 ms |
| maximum scalar | Float64 256^3 | 6.001 ms | 5.963 ms | 6.464 ms | 6.097 ms | — | 12.659 ms | 3.110 ms |
| maximum scalar | Float64 64^3 | 65.163 μs | 65.394 μs | 65.038 μs | 65.172 μs | 99.451 μs | 1.634 ms | 908.699 μs |
| mean vector | Float32 128^3 | 483.492 μs | 489.901 μs | 499.163 μs | 489.610 μs | 633.756 μs | 4.808 ms | 1.550 ms |
| mean vector | Float32 256^3 | 7.029 ms | 7.008 ms | 7.463 ms | 7.021 ms | — | 16.657 ms | 5.846 ms |
| mean vector | Float32 64^3 | 40.216 μs | 41.161 μs | 41.278 μs | 40.918 μs | 162.362 μs | 1.846 ms | 979.596 μs |
| mean vector | Float64 128^3 | 1.338 ms | 1.414 ms | 1.490 ms | 1.510 ms | 657.486 μs | 5.195 ms | 1.783 ms |
| mean vector | Float64 256^3 | 14.090 ms | 13.993 ms | 14.116 ms | 13.969 ms | — | 17.799 ms | 6.922 ms |
| mean vector | Float64 64^3 | 80.319 μs | 79.502 μs | 82.197 μs | 79.706 μs | 156.311 μs | 1.913 ms | 980.351 μs |
| radial_correlation vec | Float32 128^3 | 42.802 ms | 50.618 ms | 49.091 ms | 44.361 ms | 5.783 ms | 42.875 ms | 8.925 ms |
| radial_correlation vec | Float32 256^3 | 674.471 ms | 601.507 ms | 457.543 ms | 400.305 ms | — | 185.439 ms | 35.619 ms |
| radial_correlation vec | Float32 64^3 | 4.788 ms | 6.821 ms | 6.426 ms | 6.605 ms | 1.010 ms | 19.917 ms | 2.442 ms |
| radial_correlation vec | Float64 128^3 | 92.325 ms | 89.190 ms | 58.474 ms | 56.496 ms | 9.025 ms | 52.060 ms | 59.865 ms |
| radial_correlation vec | Float64 256^3 | 865.374 ms | 740.203 ms | 590.721 ms | 538.410 ms | — | 219.151 ms | 185.404 ms |
| radial_correlation vec | Float64 64^3 | 6.470 ms | 7.559 ms | 6.861 ms | 6.522 ms | 1.413 ms | 21.203 ms | 25.904 ms |
| radial_spectrum vec | Float32 128^3 | 12.975 ms | 17.623 ms | 17.426 ms | 17.577 ms | 1.415 ms | 27.166 ms | 4.805 ms |
| radial_spectrum vec | Float32 256^3 | 119.714 ms | 119.050 ms | 136.862 ms | 125.054 ms | — | 96.772 ms | 21.562 ms |
| radial_spectrum vec | Float32 64^3 | 1.514 ms | 2.615 ms | 2.450 ms | 2.978 ms | 344.443 μs | 16.995 ms | 1.662 ms |
| radial_spectrum vec | Float64 128^3 | 15.171 ms | 17.081 ms | 18.307 ms | 17.683 ms | 1.515 ms | 29.791 ms | 38.880 ms |
| radial_spectrum vec | Float64 256^3 | 149.159 ms | 163.923 ms | 158.186 ms | 146.996 ms | — | 110.504 ms | 91.548 ms |
| radial_spectrum vec | Float64 64^3 | 1.673 ms | 2.583 ms | 2.588 ms | 3.122 ms | 380.613 μs | 16.740 ms | 19.340 ms |

