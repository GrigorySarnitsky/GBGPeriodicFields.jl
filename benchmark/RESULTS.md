# Benchmark results

Minimum time per operation; `—` = not measured for that column. Generated 2026-06-16 at commit `b89963b` on Julia 1.12.6, host `Aiporetne`. Columns below are the runs supplied; grids and element types are in the row labels. The **CPU thread sweep 1/2/4/8 and the GPU (RX 6700 XT, gfx1031, ROCm) all cover 64³–256³, every op-class incl. FFT.** The GPU sweep builds one (op-class, grid, element-type) at a time so the 256³ working set fits in 12 GB VRAM (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh`. ~10% jitter.

## fft

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 4.921 ms | 3.266 ms | 2.329 ms | 2.083 ms | 2.421 ms |
| to_physical scalar | Float32 256^3 | 114.364 ms | 70.618 ms | 49.980 ms | 41.000 ms | 7.945 ms |
| to_physical scalar | Float32 64^3 | 382.614 μs | 243.928 μs | 166.481 μs | 142.917 μs | 1.497 ms |
| to_physical scalar | Float64 128^3 | 7.855 ms | 5.724 ms | 4.680 ms | 4.464 ms | 3.750 ms |
| to_physical scalar | Float64 256^3 | 145.579 ms | 97.997 ms | 78.702 ms | 73.352 ms | 14.463 ms |
| to_physical scalar | Float64 64^3 | 700.983 μs | 406.592 μs | 285.079 μs | 260.681 μs | 1.784 ms |
| to_physical vector | Float32 128^3 | 14.860 ms | 11.309 ms | 7.919 ms | 7.394 ms | 4.595 ms |
| to_physical vector | Float32 256^3 | 345.528 ms | 257.868 ms | 163.859 ms | 135.149 ms | 14.844 ms |
| to_physical vector | Float32 64^3 | 1.267 ms | 965.245 μs | 522.386 μs | 488.123 μs | 1.776 ms |
| to_physical vector | Float64 128^3 | 34.894 ms | 29.335 ms | 19.034 ms | 17.907 ms | 8.090 ms |
| to_physical vector | Float64 256^3 | 433.086 ms | 339.808 ms | 239.798 ms | 225.792 ms | 22.812 ms |
| to_physical vector | Float64 64^3 | 2.567 ms | 2.032 ms | 1.452 ms | 1.408 ms | 2.301 ms |
| to_spectral scalar | Float32 128^3 | 4.303 ms | 2.631 ms | 1.827 ms | 1.166 ms | 2.072 ms |
| to_spectral scalar | Float32 256^3 | 111.583 ms | 66.664 ms | 44.015 ms | 34.798 ms | 5.009 ms |
| to_spectral scalar | Float32 64^3 | 361.616 μs | 208.081 μs | 128.637 μs | 103.487 μs | 1.538 ms |
| to_spectral scalar | Float64 128^3 | 7.128 ms | 4.917 ms | 3.951 ms | 3.316 ms | 3.125 ms |
| to_spectral scalar | Float64 256^3 | 162.317 ms | 103.339 ms | 74.124 ms | 63.106 ms | 12.871 ms |
| to_spectral scalar | Float64 64^3 | 623.970 μs | 352.984 μs | 222.598 μs | 179.820 μs | 1.745 ms |
| to_spectral vector | Float32 128^3 | 13.357 ms | 9.753 ms | 6.648 ms | 5.743 ms | 3.183 ms |
| to_spectral vector | Float32 256^3 | 335.546 ms | 248.543 ms | 147.491 ms | 120.182 ms | 11.819 ms |
| to_spectral vector | Float32 64^3 | 1.189 ms | 848.736 μs | 421.884 μs | 354.965 μs | 1.566 ms |
| to_spectral vector | Float64 128^3 | 32.147 ms | 27.006 ms | 16.355 ms | 14.697 ms | 6.538 ms |
| to_spectral vector | Float64 256^3 | 489.956 ms | 364.743 ms | 229.910 ms | 201.226 ms | 20.041 ms |
| to_spectral vector | Float64 64^3 | 2.305 ms | 1.825 ms | 998.370 μs | 790.050 μs | 2.151 ms |

## algebra

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 406.977 μs | 3.594 ms | 1.805 ms | 944.709 μs | 1.943 ms |
| add! scalar | Float32 256^3 | 8.051 ms | 28.784 ms | 14.379 ms | 7.579 ms | 6.480 ms |
| add! scalar | Float32 64^3 | 42.190 μs | 454.807 μs | 230.078 μs | 122.089 μs | 1.599 ms |
| add! scalar | Float64 128^3 | 1.450 ms | 3.696 ms | 1.834 ms | 1.074 ms | 2.024 ms |
| add! scalar | Float64 256^3 | 16.638 ms | 29.062 ms | 16.073 ms | 14.747 ms | 5.550 ms |
| add! scalar | Float64 64^3 | 83.855 μs | 452.884 μs | 231.771 μs | 122.588 μs | 1.494 ms |
| cross! | Float32 128^3 | 4.462 ms | 16.605 ms | 8.425 ms | 4.432 ms | 3.445 ms |
| cross! | Float32 256^3 | 41.609 ms | 134.071 ms | 68.510 ms | 37.381 ms | 14.690 ms |
| cross! | Float32 64^3 | 421.364 μs | 2.046 ms | 1.063 ms | 542.538 μs | 1.665 ms |
| cross! | Float64 128^3 | 9.526 ms | 16.626 ms | 8.472 ms | 7.267 ms | 2.603 ms |
| cross! | Float64 256^3 | 73.606 ms | 131.772 ms | 76.442 ms | 67.645 ms | 15.625 ms |
| cross! | Float64 64^3 | 456.942 μs | 1.972 ms | 1.027 ms | 528.265 μs | 1.846 ms |
| dot! vec.vec | Float32 128^3 | 2.830 ms | 6.786 ms | 3.413 ms | 1.791 ms | 2.430 ms |
| dot! vec.vec | Float32 256^3 | 24.248 ms | 54.301 ms | 28.531 ms | 16.433 ms | 9.651 ms |
| dot! vec.vec | Float32 64^3 | 328.742 μs | 834.785 μs | 420.884 μs | 221.686 μs | 1.663 ms |
| dot! vec.vec | Float64 128^3 | 4.192 ms | 6.952 ms | 3.658 ms | 2.984 ms | 2.505 ms |
| dot! vec.vec | Float64 256^3 | 35.525 ms | 54.907 ms | 33.312 ms | 29.941 ms | 9.784 ms |
| dot! vec.vec | Float64 64^3 | 344.498 μs | 830.601 μs | 430.258 μs | 220.951 μs | 1.656 ms |
| mul! tensor.vec | Float32 128^3 | 8.767 ms | 21.066 ms | 10.820 ms | 5.582 ms | 4.295 ms |
| mul! tensor.vec | Float32 256^3 | 75.102 ms | 171.026 ms | 84.751 ms | 47.684 ms | 16.892 ms |
| mul! tensor.vec | Float32 64^3 | 1.099 ms | 2.561 ms | 1.303 ms | 679.719 μs | 1.882 ms |
| mul! tensor.vec | Float64 128^3 | 13.626 ms | 21.334 ms | 11.446 ms | 9.779 ms | 4.757 ms |
| mul! tensor.vec | Float64 256^3 | 104.196 ms | 170.205 ms | 100.974 ms | 90.254 ms | 17.818 ms |
| mul! tensor.vec | Float64 64^3 | 1.104 ms | 2.542 ms | 1.292 ms | 694.348 μs | 1.951 ms |
| norm! vec | Float32 128^3 | 762.245 μs | 4.925 ms | 2.473 ms | 1.298 ms | 2.110 ms |
| norm! vec | Float32 256^3 | 10.216 ms | 39.876 ms | 19.990 ms | 10.320 ms | 7.304 ms |
| norm! vec | Float32 64^3 | 53.494 μs | 611.901 μs | 308.677 μs | 161.713 μs | 1.526 ms |
| norm! vec | Float64 128^3 | 2.095 ms | 5.239 ms | 2.594 ms | 1.627 ms | 1.434 ms |
| norm! vec | Float64 256^3 | 19.493 ms | 40.692 ms | 21.211 ms | 18.698 ms | 9.850 ms |
| norm! vec | Float64 64^3 | 157.709 μs | 625.248 μs | 316.875 μs | 167.711 μs | 1.681 ms |

## operators

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.175 ms | 8.904 ms | 4.494 ms | 2.399 ms | 2.544 ms |
| curl! vec->vec | Float32 256^3 | 41.487 ms | 70.866 ms | 37.332 ms | 21.893 ms | 10.865 ms |
| curl! vec->vec | Float32 64^3 | 630.959 μs | 1.146 ms | 576.988 μs | 309.385 μs | 1.646 ms |
| curl! vec->vec | Float64 128^3 | 6.141 ms | 9.056 ms | 5.052 ms | 3.756 ms | 3.153 ms |
| curl! vec->vec | Float64 256^3 | 55.708 ms | 72.029 ms | 46.917 ms | 37.903 ms | 13.647 ms |
| curl! vec->vec | Float64 64^3 | 536.845 μs | 1.134 ms | 569.657 μs | 304.162 μs | 1.786 ms |
| divergence! vec->scalar | Float32 128^3 | 3.486 ms | 3.644 ms | 1.847 ms | 971.934 μs | 1.957 ms |
| divergence! vec->scalar | Float32 256^3 | 27.915 ms | 29.274 ms | 14.995 ms | 9.125 ms | 5.523 ms |
| divergence! vec->scalar | Float32 64^3 | 431.945 μs | 464.333 μs | 234.909 μs | 124.864 μs | 1.537 ms |
| divergence! vec->scalar | Float64 128^3 | 3.694 ms | 3.877 ms | 2.010 ms | 1.581 ms | 2.306 ms |
| divergence! vec->scalar | Float64 256^3 | 31.829 ms | 30.553 ms | 20.587 ms | 18.448 ms | 7.090 ms |
| divergence! vec->scalar | Float64 64^3 | 406.453 μs | 459.442 μs | 232.494 μs | 126.834 μs | 344.869 μs |
| gradient! scalar->vec | Float32 128^3 | 3.757 ms | 6.183 ms | 3.112 ms | 1.635 ms | 2.377 ms |
| gradient! scalar->vec | Float32 256^3 | 30.697 ms | 49.059 ms | 24.683 ms | 15.893 ms | 7.929 ms |
| gradient! scalar->vec | Float32 64^3 | 473.993 μs | 795.708 μs | 403.130 μs | 217.879 μs | 1.681 ms |
| gradient! scalar->vec | Float64 128^3 | 3.549 ms | 6.305 ms | 3.292 ms | 2.217 ms | 2.717 ms |
| gradient! scalar->vec | Float64 256^3 | 39.167 ms | 49.150 ms | 35.931 ms | 23.895 ms | 10.338 ms |
| gradient! scalar->vec | Float64 64^3 | 365.274 μs | 787.674 μs | 402.125 μs | 217.683 μs | 1.872 ms |
| helmholtz! vec->vec | Float32 128^3 | 23.584 ms | 19.664 ms | 9.925 ms | 5.202 ms | 4.174 ms |
| helmholtz! vec->vec | Float32 256^3 | 187.093 ms | 157.101 ms | 79.594 ms | 41.711 ms | 16.637 ms |
| helmholtz! vec->vec | Float32 64^3 | 2.994 ms | 2.502 ms | 1.263 ms | 663.256 μs | 1.935 ms |
| helmholtz! vec->vec | Float64 128^3 | 24.305 ms | 20.636 ms | 10.252 ms | 5.981 ms | 5.921 ms |
| helmholtz! vec->vec | Float64 256^3 | 195.713 ms | 164.003 ms | 82.823 ms | 57.922 ms | 18.240 ms |
| helmholtz! vec->vec | Float64 64^3 | 3.014 ms | 2.566 ms | 1.335 ms | 689.484 μs | 2.260 ms |
| laplacian! scalar | Float32 128^3 | 2.022 ms | 2.708 ms | 1.346 ms | 706.183 μs | 1.910 ms |
| laplacian! scalar | Float32 256^3 | 16.489 ms | 21.343 ms | 10.689 ms | 5.805 ms | 5.490 ms |
| laplacian! scalar | Float32 64^3 | 248.603 μs | 339.201 μs | 173.484 μs | 93.209 μs | 1.563 ms |
| laplacian! scalar | Float64 128^3 | 2.065 ms | 2.762 ms | 1.387 ms | 722.119 μs | 1.957 ms |
| laplacian! scalar | Float64 256^3 | 16.916 ms | 21.940 ms | 11.782 ms | 9.227 ms | 4.740 ms |
| laplacian! scalar | Float64 64^3 | 252.423 μs | 346.302 μs | 178.684 μs | 94.285 μs | 1.586 ms |

## convolution

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.829 ms | 2.204 ms | 1.109 ms | 582.774 μs | 1.855 ms |
| assignment_window | Float32 256^3 | 26.643 ms | 23.922 ms | 12.144 ms | 6.473 ms | 3.952 ms |
| assignment_window | Float32 64^3 | 224.966 μs | 283.827 μs | 144.905 μs | 78.552 μs | 1.640 ms |
| assignment_window | Float64 128^3 | 1.863 ms | 2.195 ms | 1.107 ms | 668.491 μs | 1.901 ms |
| assignment_window | Float64 256^3 | 39.229 ms | 30.461 ms | 15.728 ms | 8.893 ms | 4.237 ms |
| assignment_window | Float64 64^3 | 229.129 μs | 279.351 μs | 149.425 μs | 80.960 μs | 1.542 ms |
| convolve! scalar | Float32 128^3 | 1.588 ms | 2.068 ms | 1.058 ms | 543.501 μs | 1.755 ms |
| convolve! scalar | Float32 256^3 | 13.116 ms | 16.384 ms | 8.267 ms | 6.674 ms | 3.659 ms |
| convolve! scalar | Float32 64^3 | 198.678 μs | 265.213 μs | 133.517 μs | 72.159 μs | 1.480 ms |
| convolve! scalar | Float64 128^3 | 1.738 ms | 2.097 ms | 1.259 ms | 910.578 μs | 1.784 ms |
| convolve! scalar | Float64 256^3 | 18.070 ms | 17.350 ms | 13.039 ms | 11.563 ms | 4.442 ms |
| convolve! scalar | Float64 64^3 | 175.758 μs | 259.129 μs | 131.987 μs | 71.295 μs | 1.618 ms |
| convolve! vector | Float32 128^3 | 5.884 ms | 8.948 ms | 4.580 ms | 2.375 ms | 2.557 ms |
| convolve! vector | Float32 256^3 | 47.268 ms | 70.960 ms | 35.591 ms | 21.661 ms | 10.821 ms |
| convolve! vector | Float32 64^3 | 719.138 μs | 1.139 ms | 571.421 μs | 300.204 μs | 1.595 ms |
| convolve! vector | Float64 128^3 | 6.429 ms | 9.149 ms | 4.969 ms | 3.829 ms | 2.910 ms |
| convolve! vector | Float64 256^3 | 56.416 ms | 73.087 ms | 45.499 ms | 38.443 ms | 12.297 ms |
| convolve! vector | Float64 64^3 | 692.099 μs | 1.149 ms | 589.372 μs | 301.735 μs | 1.655 ms |
| spectral_band | Float32 128^3 | 4.150 ms | 3.349 ms | 1.715 ms | 879.220 μs | 2.050 ms |
| spectral_band | Float32 256^3 | 44.280 ms | 32.960 ms | 16.590 ms | 8.797 ms | 6.344 ms |
| spectral_band | Float32 64^3 | 528.608 μs | 427.300 μs | 218.491 μs | 116.205 μs | 1.537 ms |
| spectral_band | Float64 128^3 | 4.206 ms | 3.384 ms | 1.703 ms | 937.243 μs | 2.105 ms |
| spectral_band | Float64 256^3 | 56.756 ms | 39.813 ms | 20.342 ms | 11.010 ms | 5.611 ms |
| spectral_band | Float64 64^3 | 535.882 μs | 432.790 μs | 220.193 μs | 117.818 μs | 1.651 ms |
| spectral_cutoff | Float32 128^3 | 4.155 ms | 3.346 ms | 1.680 ms | 878.905 μs | 2.046 ms |
| spectral_cutoff | Float32 256^3 | 44.259 ms | 32.952 ms | 16.564 ms | 8.892 ms | 5.403 ms |
| spectral_cutoff | Float32 64^3 | 530.976 μs | 427.338 μs | 215.903 μs | 116.778 μs | 1.625 ms |
| spectral_cutoff | Float64 128^3 | 4.188 ms | 3.389 ms | 1.707 ms | 950.943 μs | 2.120 ms |
| spectral_cutoff | Float64 256^3 | 56.770 ms | 39.837 ms | 20.331 ms | 11.147 ms | 5.621 ms |
| spectral_cutoff | Float64 64^3 | 541.372 μs | 432.883 μs | 219.074 μs | 119.139 μs | 1.647 ms |
| squared_wavenumber_field | Float32 128^3 | 1.848 ms | 2.192 ms | 1.103 ms | 593.500 μs | 1.824 ms |
| squared_wavenumber_field | Float32 256^3 | 26.617 ms | 23.931 ms | 12.127 ms | 6.438 ms | 3.812 ms |
| squared_wavenumber_field | Float32 64^3 | 223.753 μs | 281.132 μs | 142.710 μs | 76.793 μs | 1.517 ms |
| squared_wavenumber_field | Float64 128^3 | 1.876 ms | 2.175 ms | 1.120 ms | 651.655 μs | 1.805 ms |
| squared_wavenumber_field | Float64 256^3 | 39.190 ms | 30.276 ms | 15.640 ms | 8.862 ms | 4.151 ms |
| squared_wavenumber_field | Float64 64^3 | 227.660 μs | 281.210 μs | 143.148 μs | 79.310 μs | 1.612 ms |

## transfer

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.486 ms | 13.693 ms | 7.379 ms | 4.666 ms | 4.864 ms |
| anterpolate! CatmullRom | Float32 256^3 | 388.713 ms | 201.712 ms | 108.330 ms | 67.130 ms | 17.932 ms |
| anterpolate! CatmullRom | Float32 64^3 | 3.166 ms | 1.837 ms | 1.206 ms | 861.307 μs | 2.057 ms |
| anterpolate! CatmullRom | Float64 128^3 | 29.059 ms | 14.941 ms | 7.548 ms | 4.560 ms | 4.862 ms |
| anterpolate! CatmullRom | Float64 256^3 | 490.336 ms | 264.731 ms | 150.411 ms | 102.832 ms | 19.810 ms |
| anterpolate! CatmullRom | Float64 64^3 | 3.317 ms | 1.872 ms | 1.238 ms | 917.933 μs | 2.004 ms |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 195.878 ms | 100.304 ms | 50.753 ms | 28.451 ms | 15.478 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.236 s | 1.157 s | 681.272 ms | 501.054 ms | 48.567 ms |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.851 ms | 13.119 ms | 8.135 ms | 5.593 ms | 5.959 ms |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 205.748 ms | 105.711 ms | 52.796 ms | 29.507 ms | 16.564 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.545 s | 1.408 s | 853.867 ms | 618.332 ms | 66.043 ms |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.364 ms | 13.250 ms | 8.320 ms | 5.645 ms | 5.503 ms |
| anterpolate! NUFFT | Float32 128^3 | 417.604 ms | 237.509 ms | 149.510 ms | 113.905 ms | 18.762 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.340 s | 2.420 s | 1.483 s | 1.103 s | 120.799 ms |
| anterpolate! NUFFT | Float32 64^3 | 31.886 ms | 18.004 ms | 11.150 ms | 8.367 ms | 6.296 ms |
| anterpolate! NUFFT | Float64 128^3 | 534.863 ms | 321.231 ms | 218.870 ms | 178.857 ms | 22.503 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.005 s | 2.955 s | 1.889 s | 1.526 s | 160.735 ms |
| anterpolate! NUFFT | Float64 64^3 | 36.277 ms | 21.348 ms | 14.358 ms | 10.660 ms | 8.203 ms |
| anterpolate! trilinear | Float32 128^3 | 4.638 ms | 2.283 ms | 1.299 ms | 867.690 μs | 2.018 ms |
| anterpolate! trilinear | Float32 256^3 | 80.684 ms | 44.216 ms | 25.632 ms | 18.598 ms | 6.631 ms |
| anterpolate! trilinear | Float32 64^3 | 481.530 μs | 321.325 μs | 211.207 μs | 168.148 μs | 1.565 ms |
| anterpolate! trilinear | Float64 128^3 | 5.280 ms | 2.763 ms | 1.558 ms | 1.066 ms | 1.980 ms |
| anterpolate! trilinear | Float64 256^3 | 90.482 ms | 51.919 ms | 34.350 ms | 27.048 ms | 6.838 ms |
| anterpolate! trilinear | Float64 64^3 | 519.949 μs | 338.641 μs | 241.519 μs | 191.472 μs | 1.554 ms |
| interpolate! CatmullRom | Float32 128^3 | 11.498 ms | 5.828 ms | 2.940 ms | 1.612 ms | 3.140 ms |
| interpolate! CatmullRom | Float32 256^3 | 264.919 ms | 138.857 ms | 74.296 ms | 44.901 ms | 14.577 ms |
| interpolate! CatmullRom | Float32 64^3 | 1.304 ms | 708.859 μs | 428.445 μs | 298.072 μs | 1.724 ms |
| interpolate! CatmullRom | Float64 128^3 | 13.118 ms | 7.284 ms | 3.568 ms | 1.844 ms | 2.789 ms |
| interpolate! CatmullRom | Float64 256^3 | 293.824 ms | 159.415 ms | 92.206 ms | 60.215 ms | 12.939 ms |
| interpolate! CatmullRom | Float64 64^3 | 1.361 ms | 737.024 μs | 451.505 μs | 313.918 μs | 1.759 ms |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.494 ms | 37.299 ms | 18.811 ms | 10.311 ms | 14.027 ms |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.396 s | 767.141 ms | 493.281 ms | 326.516 ms | 30.216 ms |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.714 ms | 4.707 ms | 2.884 ms | 1.935 ms | 3.166 ms |
| interpolate! Lalescu(3,3) | Float64 128^3 | 82.236 ms | 45.114 ms | 21.920 ms | 11.704 ms | 9.517 ms |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.755 s | 1.015 s | 679.057 ms | 436.527 ms | 28.103 ms |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.960 ms | 4.824 ms | 2.948 ms | 2.010 ms | 3.595 ms |
| interpolate! NUFFT | Float32 128^3 | 322.608 ms | 193.680 ms | 133.018 ms | 101.434 ms | 16.422 ms |
| interpolate! NUFFT | Float32 256^3 | 3.599 s | 2.076 s | 1.360 s | 994.315 ms | 72.243 ms |
| interpolate! NUFFT | Float32 64^3 | 16.790 ms | 10.223 ms | 6.942 ms | 5.279 ms | 4.302 ms |
| interpolate! NUFFT | Float64 128^3 | 423.788 ms | 265.673 ms | 194.416 ms | 160.598 ms | 18.237 ms |
| interpolate! NUFFT | Float64 256^3 | 3.919 s | 2.356 s | 1.680 s | 1.360 s | 118.516 ms |
| interpolate! NUFFT | Float64 64^3 | 21.223 ms | 14.154 ms | 10.673 ms | 8.925 ms | 6.116 ms |
| interpolate! trilinear | Float32 128^3 | 1.995 ms | 1.020 ms | 527.574 μs | 286.609 μs | 1.719 ms |
| interpolate! trilinear | Float32 256^3 | 53.430 ms | 28.098 ms | 15.110 ms | 8.963 ms | 3.594 ms |
| interpolate! trilinear | Float32 64^3 | 224.378 μs | 126.441 μs | 78.131 μs | 55.955 μs | 1.448 ms |
| interpolate! trilinear | Float64 128^3 | 2.372 ms | 1.372 ms | 674.165 μs | 340.517 μs | 1.772 ms |
| interpolate! trilinear | Float64 256^3 | 58.723 ms | 32.808 ms | 20.524 ms | 13.451 ms | 4.014 ms |
| interpolate! trilinear | Float64 64^3 | 238.579 μs | 133.571 μs | 81.905 μs | 57.810 μs | 1.530 ms |

## reductions

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 14.975 ms | 19.839 ms | 19.805 ms | 19.403 ms | 27.761 ms |
| co-spectrum vec.vec | Float32 256^3 | 155.191 ms | 164.249 ms | 164.446 ms | 153.605 ms | 97.666 ms |
| co-spectrum vec.vec | Float32 64^3 | 1.620 ms | 2.739 ms | 2.755 ms | 3.066 ms | 17.761 ms |
| co-spectrum vec.vec | Float64 128^3 | 19.182 ms | 20.856 ms | 22.230 ms | 21.608 ms | 29.708 ms |
| co-spectrum vec.vec | Float64 256^3 | 218.682 ms | 223.349 ms | 215.442 ms | 207.881 ms | 109.563 ms |
| co-spectrum vec.vec | Float64 64^3 | 1.992 ms | 2.966 ms | 3.032 ms | 3.029 ms | 16.075 ms |
| cross-correlation vec.vec | Float32 128^3 | 45.051 ms | 50.572 ms | 44.075 ms | 47.675 ms | 43.640 ms |
| cross-correlation vec.vec | Float32 256^3 | 691.628 ms | 623.062 ms | 457.282 ms | 405.787 ms | 186.915 ms |
| cross-correlation vec.vec | Float32 64^3 | 5.066 ms | 7.246 ms | 6.444 ms | 6.782 ms | 20.682 ms |
| cross-correlation vec.vec | Float64 128^3 | 91.058 ms | 71.859 ms | 61.365 ms | 60.835 ms | 52.055 ms |
| cross-correlation vec.vec | Float64 256^3 | 890.182 ms | 763.266 ms | 600.145 ms | 556.480 ms | 217.471 ms |
| cross-correlation vec.vec | Float64 64^3 | 6.613 ms | 7.735 ms | 7.204 ms | 6.645 ms | 20.881 ms |
| inner spectral | Float32 128^3 | 1.499 ms | 1.570 ms | 1.519 ms | 1.473 ms | 2.049 ms |
| inner spectral | Float32 256^3 | 15.411 ms | 15.859 ms | 15.730 ms | 15.392 ms | 3.999 ms |
| inner spectral | Float32 64^3 | 145.455 μs | 145.246 μs | 145.205 μs | 144.860 μs | 1.780 ms |
| inner spectral | Float64 128^3 | 2.943 ms | 2.958 ms | 2.954 ms | 2.960 ms | 2.410 ms |
| inner spectral | Float64 256^3 | 26.783 ms | 27.189 ms | 26.774 ms | 26.747 ms | 7.953 ms |
| inner spectral | Float64 64^3 | 117.554 μs | 118.581 μs | 118.459 μs | 120.147 μs | 1.765 ms |
| inner vec.vec | Float32 128^3 | 1.149 ms | 1.221 ms | 1.143 ms | 1.170 ms | 1.623 ms |
| inner vec.vec | Float32 256^3 | 12.686 ms | 12.631 ms | 12.704 ms | 12.665 ms | 3.382 ms |
| inner vec.vec | Float32 64^3 | 64.992 μs | 65.900 μs | 64.765 μs | 64.789 μs | 1.278 ms |
| inner vec.vec | Float64 128^3 | 2.216 ms | 2.153 ms | 2.193 ms | 2.167 ms | 1.860 ms |
| inner vec.vec | Float64 256^3 | 22.172 ms | 22.218 ms | 22.175 ms | 22.154 ms | 5.634 ms |
| inner vec.vec | Float64 64^3 | 30.399 μs | 32.911 μs | 33.240 μs | 33.862 μs | 1.434 ms |
| integral scalar | Float32 128^3 | 109.722 μs | 109.285 μs | 109.246 μs | 109.743 μs | 1.318 ms |
| integral scalar | Float32 256^3 | 2.060 ms | 2.042 ms | 2.026 ms | 1.971 ms | 9.002 ms |
| integral scalar | Float32 64^3 | 9.593 μs | 11.150 μs | 11.314 μs | 10.325 μs | 1.534 ms |
| integral scalar | Float64 128^3 | 211.954 μs | 230.409 μs | 218.985 μs | 232.194 μs | 2.553 ms |
| integral scalar | Float64 256^3 | 4.439 ms | 4.453 ms | 4.442 ms | 5.021 ms | 10.817 ms |
| integral scalar | Float64 64^3 | 26.595 μs | 27.364 μs | 26.677 μs | 26.122 μs | 1.583 ms |
| l2norm vec | Float32 128^3 | 432.140 μs | 452.407 μs | 453.241 μs | 449.136 μs | 1.582 ms |
| l2norm vec | Float32 256^3 | 6.536 ms | 6.517 ms | 6.526 ms | 6.506 ms | 3.219 ms |
| l2norm vec | Float32 64^3 | 39.665 μs | 39.610 μs | 43.111 μs | 39.714 μs | 1.361 ms |
| l2norm vec | Float64 128^3 | 728.943 μs | 775.945 μs | 727.122 μs | 744.577 μs | 1.876 ms |
| l2norm vec | Float64 256^3 | 11.092 ms | 11.023 ms | 11.036 ms | 11.070 ms | 5.670 ms |
| l2norm vec | Float64 64^3 | 16.153 μs | 16.296 μs | 17.894 μs | 17.820 μs | 1.402 ms |
| lpnorm vec Inf | Float32 128^3 | 1.405 ms | 5.374 ms | 3.003 ms | 1.881 ms | 3.080 ms |
| lpnorm vec Inf | Float32 256^3 | 22.064 ms | 50.455 ms | 25.942 ms | 19.120 ms | 13.216 ms |
| lpnorm vec Inf | Float32 64^3 | 95.815 μs | 655.556 μs | 360.399 μs | 217.048 μs | 1.641 ms |
| lpnorm vec Inf | Float64 128^3 | 2.996 ms | 6.505 ms | 3.795 ms | 2.860 ms | 3.883 ms |
| lpnorm vec Inf | Float64 256^3 | 44.798 ms | 59.647 ms | 33.669 ms | 22.256 ms | 14.730 ms |
| lpnorm vec Inf | Float64 64^3 | 229.520 μs | 737.496 μs | 429.361 μs | 268.407 μs | 1.711 ms |
| maximum scalar | Float32 128^3 | 334.168 μs | 334.303 μs | 334.994 μs | 336.401 μs | 2.331 ms |
| maximum scalar | Float32 256^3 | 2.882 ms | 2.888 ms | 2.851 ms | 2.833 ms | 9.121 ms |
| maximum scalar | Float32 64^3 | 41.632 μs | 41.674 μs | 41.756 μs | 41.935 μs | 1.564 ms |
| maximum scalar | Float64 128^3 | 522.159 μs | 537.304 μs | 528.521 μs | 541.726 μs | 2.772 ms |
| maximum scalar | Float64 256^3 | 5.983 ms | 5.963 ms | 5.936 ms | 6.664 ms | 12.659 ms |
| maximum scalar | Float64 64^3 | 65.166 μs | 65.394 μs | 65.301 μs | 65.080 μs | 1.634 ms |
| mean vector | Float32 128^3 | 441.475 μs | 489.901 μs | 463.351 μs | 456.964 μs | 4.808 ms |
| mean vector | Float32 256^3 | 7.032 ms | 7.008 ms | 7.024 ms | 7.001 ms | 16.657 ms |
| mean vector | Float32 64^3 | 41.432 μs | 41.161 μs | 41.730 μs | 39.797 μs | 1.846 ms |
| mean vector | Float64 128^3 | 1.426 ms | 1.414 ms | 1.385 ms | 1.582 ms | 5.195 ms |
| mean vector | Float64 256^3 | 14.000 ms | 13.993 ms | 14.024 ms | 14.016 ms | 17.799 ms |
| mean vector | Float64 64^3 | 81.587 μs | 79.502 μs | 79.564 μs | 80.536 μs | 1.913 ms |
| radial_correlation vec | Float32 128^3 | 42.668 ms | 50.618 ms | 43.695 ms | 40.755 ms | 42.875 ms |
| radial_correlation vec | Float32 256^3 | 673.857 ms | 601.507 ms | 453.662 ms | 398.652 ms | 185.439 ms |
| radial_correlation vec | Float32 64^3 | 4.809 ms | 6.821 ms | 6.476 ms | 6.624 ms | 19.917 ms |
| radial_correlation vec | Float64 128^3 | 92.617 ms | 89.190 ms | 70.201 ms | 56.743 ms | 52.060 ms |
| radial_correlation vec | Float64 256^3 | 861.666 ms | 740.203 ms | 581.375 ms | 534.000 ms | 219.151 ms |
| radial_correlation vec | Float64 64^3 | 6.331 ms | 7.559 ms | 6.872 ms | 6.458 ms | 21.203 ms |
| radial_spectrum vec | Float32 128^3 | 12.896 ms | 17.623 ms | 17.477 ms | 17.546 ms | 27.166 ms |
| radial_spectrum vec | Float32 256^3 | 125.501 ms | 119.050 ms | 135.944 ms | 124.150 ms | 96.772 ms |
| radial_spectrum vec | Float32 64^3 | 1.511 ms | 2.615 ms | 2.576 ms | 2.976 ms | 16.995 ms |
| radial_spectrum vec | Float64 128^3 | 15.163 ms | 17.081 ms | 17.951 ms | 17.574 ms | 29.791 ms |
| radial_spectrum vec | Float64 256^3 | 157.661 ms | 163.923 ms | 155.743 ms | 147.884 ms | 110.504 ms |
| radial_spectrum vec | Float64 64^3 | 1.672 ms | 2.583 ms | 2.522 ms | 2.621 ms | 16.740 ms |

