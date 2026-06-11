# Benchmark results

Minimum time per operation; `—` = not measured for that column. Generated 2026-06-11 at commit `b738494` on Julia 1.12.6, host `Aiporetne`. Columns below are the runs supplied; grids and element types are in the row labels. The **CPU thread sweep 1/2/4/8 and the GPU (RX 6700 XT, gfx1031, ROCm) all cover 64³–256³, every op-class incl. FFT — except the GPU `reductions` column, pending a device-reset re-run.** The GPU sweep builds one (grid, element-type) at a time so 256³ fits in 12 GB VRAM (PERFORMANCE.md §6 gap 5). **Regenerate** with `benchmark/characterize.sh`. ~10% jitter.

## fft

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 4.902 ms | 3.228 ms | 2.366 ms | 2.106 ms | 264.913 μs |
| to_physical scalar | Float32 256^3 | 104.073 ms | 69.632 ms | 48.788 ms | 39.950 ms | 2.334 ms |
| to_physical scalar | Float32 64^3 | 385.595 μs | 244.744 μs | 176.202 μs | 139.807 μs | 49.751 μs |
| to_physical scalar | Float64 128^3 | 8.004 ms | 5.685 ms | 4.789 ms | 4.544 ms | 528.587 μs |
| to_physical scalar | Float64 256^3 | 96.494 ms | 64.499 ms | 50.703 ms | 60.290 ms | 6.457 ms |
| to_physical scalar | Float64 64^3 | 676.438 μs | 407.678 μs | 285.968 μs | 254.324 μs | 87.204 μs |
| to_physical vector | Float32 128^3 | 14.875 ms | 11.332 ms | 7.979 ms | 7.290 ms | 767.197 μs |
| to_physical vector | Float32 256^3 | 350.017 ms | 256.435 ms | 161.089 ms | 136.847 ms | 11.890 ms |
| to_physical vector | Float32 64^3 | 1.275 ms | 947.198 μs | 530.072 μs | 461.700 μs | 105.356 μs |
| to_physical vector | Float64 128^3 | 44.190 ms | 35.893 ms | 27.201 ms | 26.999 ms | 1.793 ms |
| to_physical vector | Float64 256^3 | 376.331 ms | 285.793 ms | 184.958 ms | 228.107 ms | 22.161 ms |
| to_physical vector | Float64 64^3 | 2.565 ms | 1.843 ms | 1.503 ms | 1.254 ms | 217.082 μs |
| to_spectral scalar | Float32 128^3 | 4.486 ms | 2.665 ms | 1.663 ms | 1.240 ms | 161.841 μs |
| to_spectral scalar | Float32 256^3 | 100.643 ms | 66.530 ms | 44.716 ms | 34.922 ms | 1.724 ms |
| to_spectral scalar | Float32 64^3 | 363.419 μs | 207.628 μs | 129.511 μs | 122.384 μs | 35.093 μs |
| to_spectral scalar | Float64 128^3 | 7.105 ms | 5.020 ms | 3.918 ms | 3.227 ms | 402.989 μs |
| to_spectral scalar | Float64 256^3 | 114.019 ms | 65.816 ms | 45.611 ms | 44.553 ms | 4.446 ms |
| to_spectral scalar | Float64 64^3 | 677.882 μs | 353.774 μs | 238.813 μs | 224.726 μs | 74.983 μs |
| to_spectral vector | Float32 128^3 | 13.349 ms | 9.688 ms | 6.477 ms | 5.873 ms | 432.167 μs |
| to_spectral vector | Float32 256^3 | 340.739 ms | 246.824 ms | 147.060 ms | 120.145 ms | 8.895 ms |
| to_spectral vector | Float32 64^3 | 1.202 ms | 845.568 μs | 410.879 μs | 364.133 μs | 57.994 μs |
| to_spectral vector | Float64 128^3 | 41.327 ms | 32.694 ms | 24.051 ms | 22.692 ms | 1.350 ms |
| to_spectral vector | Float64 256^3 | 420.889 ms | 314.122 ms | 179.757 ms | 203.817 ms | 16.524 ms |
| to_spectral vector | Float64 64^3 | 2.189 ms | 1.605 ms | 981.727 μs | 799.929 μs | 170.884 μs |

## algebra

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 403.476 μs | 3.598 ms | 1.803 ms | 945.369 μs | 117.515 μs |
| add! scalar | Float32 256^3 | 8.099 ms | 28.718 ms | 14.604 ms | 8.014 ms | 839.609 μs |
| add! scalar | Float32 64^3 | 42.252 μs | 453.680 μs | 229.956 μs | 121.468 μs | 31.534 μs |
| add! scalar | Float64 128^3 | 1.472 ms | 3.634 ms | 1.865 ms | 1.060 ms | 123.011 μs |
| add! scalar | Float64 256^3 | 16.939 ms | 29.126 ms | 16.235 ms | 14.702 ms | 1.251 ms |
| add! scalar | Float64 64^3 | 83.918 μs | 459.657 μs | 234.765 μs | 121.778 μs | 32.230 μs |
| cross! | Float32 128^3 | 4.579 ms | 16.647 ms | 8.333 ms | 4.432 ms | 443.032 μs |
| cross! | Float32 256^3 | 41.384 ms | 134.056 ms | 67.858 ms | 36.204 ms | 3.409 ms |
| cross! | Float32 64^3 | 423.156 μs | 2.056 ms | 1.028 ms | 543.171 μs | 78.104 μs |
| cross! | Float64 128^3 | 9.498 ms | 16.125 ms | 8.578 ms | 7.368 ms | 532.683 μs |
| cross! | Float64 256^3 | 74.875 ms | 132.439 ms | 78.354 ms | 68.483 ms | 6.127 ms |
| cross! | Float64 64^3 | 474.523 μs | 2.007 ms | 1.043 ms | 526.353 μs | 87.153 μs |
| dot! vec.vec | Float32 128^3 | 2.859 ms | 6.793 ms | 3.395 ms | 1.793 ms | 208.017 μs |
| dot! vec.vec | Float32 256^3 | 24.105 ms | 54.805 ms | 27.407 ms | 16.222 ms | 1.580 ms |
| dot! vec.vec | Float32 64^3 | 330.080 μs | 842.335 μs | 422.674 μs | 221.727 μs | 46.437 μs |
| dot! vec.vec | Float64 128^3 | 4.167 ms | 6.788 ms | 3.651 ms | 3.171 ms | 302.505 μs |
| dot! vec.vec | Float64 256^3 | 38.218 ms | 55.119 ms | 32.782 ms | 30.356 ms | 2.728 ms |
| dot! vec.vec | Float64 64^3 | 339.154 μs | 881.433 μs | 424.995 μs | 220.761 μs | 45.666 μs |
| mul! tensor.vec | Float32 128^3 | 9.054 ms | 21.034 ms | 10.836 ms | 5.615 ms | 607.056 μs |
| mul! tensor.vec | Float32 256^3 | 82.223 ms | 173.130 ms | 86.002 ms | 48.591 ms | 4.980 ms |
| mul! tensor.vec | Float32 64^3 | 1.098 ms | 2.603 ms | 1.331 ms | 688.932 μs | 103.191 μs |
| mul! tensor.vec | Float64 128^3 | 13.746 ms | 21.047 ms | 11.292 ms | 9.971 ms | 970.230 μs |
| mul! tensor.vec | Float64 256^3 | 108.516 ms | 171.343 ms | 101.516 ms | 91.036 ms | 8.777 ms |
| mul! tensor.vec | Float64 64^3 | 1.132 ms | 2.620 ms | 1.313 ms | 685.880 μs | 107.945 μs |
| norm! vec | Float32 128^3 | 725.471 μs | 4.994 ms | 2.517 ms | 1.299 ms | 142.491 μs |
| norm! vec | Float32 256^3 | 10.001 ms | 39.621 ms | 20.086 ms | 10.411 ms | 1.029 ms |
| norm! vec | Float32 64^3 | 53.366 μs | 610.549 μs | 306.891 μs | 161.001 μs | 35.483 μs |
| norm! vec | Float64 128^3 | 2.091 ms | 5.006 ms | 2.515 ms | 1.600 ms | 227.950 μs |
| norm! vec | Float64 256^3 | 19.633 ms | 40.508 ms | 21.108 ms | 18.986 ms | 1.720 ms |
| norm! vec | Float64 64^3 | 157.672 μs | 645.725 μs | 323.725 μs | 166.180 μs | 46.339 μs |

## operators

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.189 ms | 9.087 ms | 4.557 ms | 2.399 ms | 260.691 μs |
| curl! vec->vec | Float32 256^3 | 41.684 ms | 70.995 ms | 36.793 ms | 23.981 ms | 1.945 ms |
| curl! vec->vec | Float32 64^3 | 631.028 μs | 1.147 ms | 581.621 μs | 309.724 μs | 60.912 μs |
| curl! vec->vec | Float64 128^3 | 6.181 ms | 9.063 ms | 5.233 ms | 3.680 ms | 358.456 μs |
| curl! vec->vec | Float64 256^3 | 54.310 ms | 72.156 ms | 49.284 ms | 38.387 ms | 3.929 ms |
| curl! vec->vec | Float64 64^3 | 541.359 μs | 1.120 ms | 574.307 μs | 303.989 μs | 73.896 μs |
| divergence! vec->scalar | Float32 128^3 | 3.524 ms | 3.746 ms | 1.886 ms | 996.177 μs | 119.045 μs |
| divergence! vec->scalar | Float32 256^3 | 27.979 ms | 29.071 ms | 15.029 ms | 9.289 ms | 898.916 μs |
| divergence! vec->scalar | Float32 64^3 | 417.239 μs | 466.026 μs | 234.700 μs | 124.953 μs | 36.057 μs |
| divergence! vec->scalar | Float64 128^3 | 3.644 ms | 3.805 ms | 2.058 ms | 1.606 ms | 158.536 μs |
| divergence! vec->scalar | Float64 256^3 | 29.751 ms | 30.625 ms | 20.794 ms | 18.860 ms | 1.690 ms |
| divergence! vec->scalar | Float64 64^3 | 407.296 μs | 457.286 μs | 233.978 μs | 123.414 μs | 40.274 μs |
| gradient! scalar->vec | Float32 128^3 | 3.767 ms | 6.194 ms | 3.175 ms | 1.651 ms | 196.351 μs |
| gradient! scalar->vec | Float32 256^3 | 30.791 ms | 49.212 ms | 25.131 ms | 17.127 ms | 1.385 ms |
| gradient! scalar->vec | Float32 64^3 | 472.376 μs | 794.825 μs | 404.433 μs | 217.561 μs | 52.334 μs |
| gradient! scalar->vec | Float64 128^3 | 3.864 ms | 6.091 ms | 3.255 ms | 2.169 ms | 267.061 μs |
| gradient! scalar->vec | Float64 256^3 | 38.668 ms | 48.962 ms | 33.890 ms | 26.315 ms | 2.725 ms |
| gradient! scalar->vec | Float64 64^3 | 365.212 μs | 780.053 μs | 406.232 μs | 217.584 μs | 59.495 μs |
| helmholtz! vec->vec | Float32 128^3 | 7.278 ms | 10.773 ms | 7.615 ms | 6.384 ms | 471.344 μs |
| helmholtz! vec->vec | Float32 256^3 | 61.009 ms | 102.494 ms | 75.762 ms | 69.823 ms | 3.731 ms |
| helmholtz! vec->vec | Float32 64^3 | 813.888 μs | 1.380 ms | 946.221 μs | 791.688 μs | 99.455 μs |
| helmholtz! vec->vec | Float64 128^3 | 11.521 ms | 12.877 ms | 11.015 ms | 9.663 ms | 628.562 μs |
| helmholtz! vec->vec | Float64 256^3 | 94.892 ms | 135.157 ms | 110.282 ms | 103.688 ms | 8.350 ms |
| helmholtz! vec->vec | Float64 64^3 | 979.504 μs | 1.538 ms | 1.088 ms | 898.792 μs | 115.246 μs |
| laplacian! scalar | Float32 128^3 | 1.892 ms | 2.434 ms | 1.577 ms | 1.097 ms | 190.254 μs |
| laplacian! scalar | Float32 256^3 | 16.042 ms | 24.789 ms | 18.682 ms | 16.469 ms | 1.301 ms |
| laplacian! scalar | Float32 64^3 | 199.906 μs | 272.273 μs | 160.504 μs | 119.454 μs | 52.204 μs |
| laplacian! scalar | Float64 128^3 | 2.958 ms | 3.420 ms | 2.763 ms | 2.353 ms | 210.444 μs |
| laplacian! scalar | Float64 256^3 | 26.593 ms | 29.552 ms | 23.767 ms | 38.483 ms | 2.203 ms |
| laplacian! scalar | Float64 64^3 | 239.522 μs | 323.766 μs | 205.270 μs | 184.342 μs | 52.611 μs |

## transfer

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.492 ms | 13.755 ms | 7.310 ms | 4.394 ms | 641.724 μs |
| anterpolate! CatmullRom | Float32 256^3 | 392.487 ms | 206.253 ms | 110.301 ms | 68.398 ms | 4.896 ms |
| anterpolate! CatmullRom | Float32 64^3 | 3.190 ms | 1.860 ms | 1.201 ms | 858.844 μs | 126.569 μs |
| anterpolate! CatmullRom | Float64 128^3 | 31.707 ms | 14.857 ms | 7.481 ms | 4.591 ms | 667.050 μs |
| anterpolate! CatmullRom | Float64 256^3 | 496.410 ms | 263.180 ms | 148.441 ms | 102.629 ms | 8.886 ms |
| anterpolate! CatmullRom | Float64 64^3 | 3.312 ms | 1.872 ms | 1.238 ms | 938.929 μs | 133.076 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 198.264 ms | 100.548 ms | 51.144 ms | 28.618 ms | 4.861 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.267 s | 1.181 s | 688.631 ms | 514.472 ms | 35.838 ms |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.927 ms | 13.124 ms | 8.185 ms | 5.602 ms | 824.788 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 216.484 ms | 105.505 ms | 52.505 ms | 29.672 ms | 4.584 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.599 s | 1.397 s | 851.948 ms | 624.749 ms | 55.994 ms |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.370 ms | 13.375 ms | 8.322 ms | 5.834 ms | 768.518 μs |
| anterpolate! trilinear | Float32 128^3 | 4.482 ms | 2.327 ms | 1.307 ms | 872.136 μs | 132.234 μs |
| anterpolate! trilinear | Float32 256^3 | 79.823 ms | 43.659 ms | 26.040 ms | 18.743 ms | 1.046 ms |
| anterpolate! trilinear | Float32 64^3 | 491.790 μs | 308.800 μs | 218.053 μs | 162.089 μs | 38.018 μs |
| anterpolate! trilinear | Float64 128^3 | 5.850 ms | 2.717 ms | 1.513 ms | 1.090 ms | 145.025 μs |
| anterpolate! trilinear | Float64 256^3 | 89.608 ms | 51.408 ms | 33.253 ms | 26.961 ms | 1.702 ms |
| anterpolate! trilinear | Float64 64^3 | 515.924 μs | 337.699 μs | 240.810 μs | 200.718 μs | 41.477 μs |
| interpolate! CatmullRom | Float32 128^3 | 11.534 ms | 5.819 ms | 2.998 ms | 1.615 ms | 333.322 μs |
| interpolate! CatmullRom | Float32 256^3 | 267.686 ms | 138.682 ms | 74.492 ms | 45.515 ms | 2.093 ms |
| interpolate! CatmullRom | Float32 64^3 | 1.313 ms | 709.342 μs | 434.795 μs | 299.527 μs | 76.935 μs |
| interpolate! CatmullRom | Float64 128^3 | 16.742 ms | 7.017 ms | 3.294 ms | 1.950 ms | 276.733 μs |
| interpolate! CatmullRom | Float64 256^3 | 295.063 ms | 154.555 ms | 87.537 ms | 59.624 ms | 2.799 ms |
| interpolate! CatmullRom | Float64 64^3 | 1.361 ms | 739.703 μs | 442.242 μs | 320.856 μs | 72.883 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.643 ms | 37.404 ms | 19.137 ms | 10.508 ms | 2.429 ms |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.412 s | 793.112 ms | 501.872 ms | 326.114 ms | 17.512 ms |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.748 ms | 4.711 ms | 2.881 ms | 1.945 ms | 362.343 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 98.060 ms | 45.113 ms | 21.433 ms | 12.158 ms | 1.572 ms |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.779 s | 1.005 s | 657.814 ms | 442.534 ms | 16.928 ms |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.964 ms | 4.862 ms | 2.929 ms | 2.010 ms | 438.248 μs |
| interpolate! trilinear | Float32 128^3 | 1.989 ms | 1.018 ms | 528.288 μs | 287.302 μs | 51.155 μs |
| interpolate! trilinear | Float32 256^3 | 53.778 ms | 27.599 ms | 15.095 ms | 9.093 ms | 284.048 μs |
| interpolate! trilinear | Float32 64^3 | 228.120 μs | 125.236 μs | 78.829 μs | 55.736 μs | 25.703 μs |
| interpolate! trilinear | Float64 128^3 | 3.272 ms | 1.284 ms | 584.209 μs | 378.606 μs | 64.945 μs |
| interpolate! trilinear | Float64 256^3 | 57.963 ms | 31.359 ms | 19.671 ms | 13.208 ms | 480.581 μs |
| interpolate! trilinear | Float64 64^3 | 237.877 μs | 132.067 μs | 81.366 μs | 56.813 μs | 29.964 μs |

## reductions

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| inner vec.vec | Float32 128^3 | 1.185 ms | 1.196 ms | 1.188 ms | 1.146 ms | — |
| inner vec.vec | Float32 256^3 | 12.424 ms | 12.343 ms | 12.416 ms | 12.533 ms | — |
| inner vec.vec | Float32 64^3 | 65.781 μs | 64.852 μs | 65.847 μs | 64.794 μs | — |
| inner vec.vec | Float64 128^3 | 2.141 ms | 2.152 ms | 2.202 ms | 2.159 ms | — |
| inner vec.vec | Float64 256^3 | 22.235 ms | 22.073 ms | 22.240 ms | 22.222 ms | — |
| inner vec.vec | Float64 64^3 | 33.122 μs | 33.364 μs | 29.857 μs | 30.671 μs | — |
| integral scalar | Float32 128^3 | 108.629 μs | 105.935 μs | 109.627 μs | 111.441 μs | — |
| integral scalar | Float32 256^3 | 2.051 ms | 2.076 ms | 2.052 ms | 2.004 ms | — |
| integral scalar | Float32 64^3 | 9.621 μs | 10.424 μs | 11.506 μs | 10.489 μs | — |
| integral scalar | Float64 128^3 | 214.833 μs | 216.820 μs | 221.165 μs | 230.216 μs | — |
| integral scalar | Float64 256^3 | 4.438 ms | 4.464 ms | 4.482 ms | 4.467 ms | — |
| integral scalar | Float64 64^3 | 26.123 μs | 25.807 μs | 25.782 μs | 26.034 μs | — |
| l2norm vec | Float32 128^3 | 403.008 μs | 446.854 μs | 401.311 μs | 436.015 μs | — |
| l2norm vec | Float32 256^3 | 6.549 ms | 6.543 ms | 6.526 ms | 6.652 ms | — |
| l2norm vec | Float32 64^3 | 39.673 μs | 39.622 μs | 39.649 μs | 39.697 μs | — |
| l2norm vec | Float64 128^3 | 715.967 μs | 741.848 μs | 727.025 μs | 744.921 μs | — |
| l2norm vec | Float64 256^3 | 11.039 ms | 11.133 ms | 11.157 ms | 11.068 ms | — |
| l2norm vec | Float64 64^3 | 16.259 μs | 16.524 μs | 11.567 μs | 16.595 μs | — |
| lpnorm vec Inf | Float32 128^3 | 1.338 ms | 5.510 ms | 3.100 ms | 1.925 ms | — |
| lpnorm vec Inf | Float32 256^3 | 14.249 ms | 48.510 ms | 26.037 ms | 15.350 ms | — |
| lpnorm vec Inf | Float32 64^3 | 97.129 μs | 655.780 μs | 363.677 μs | 217.001 μs | — |
| lpnorm vec Inf | Float64 128^3 | 3.098 ms | 6.070 ms | 3.950 ms | 2.884 ms | — |
| lpnorm vec Inf | Float64 256^3 | 27.540 ms | 50.389 ms | 28.787 ms | 22.284 ms | — |
| lpnorm vec Inf | Float64 64^3 | 230.864 μs | 743.522 μs | 430.937 μs | 269.601 μs | — |
| maximum scalar | Float32 128^3 | 336.529 μs | 336.461 μs | 334.772 μs | 336.846 μs | — |
| maximum scalar | Float32 256^3 | 2.833 ms | 3.691 ms | 3.662 ms | 2.830 ms | — |
| maximum scalar | Float32 64^3 | 41.940 μs | 41.996 μs | 41.764 μs | 41.805 μs | — |
| maximum scalar | Float64 128^3 | 523.857 μs | 525.363 μs | 533.954 μs | 537.752 μs | — |
| maximum scalar | Float64 256^3 | 5.989 ms | 5.950 ms | 6.034 ms | 5.989 ms | — |
| maximum scalar | Float64 64^3 | 65.064 μs | 65.009 μs | 65.034 μs | 65.106 μs | — |
| mean vector | Float32 128^3 | 425.069 μs | 463.520 μs | 432.408 μs | 449.068 μs | — |
| mean vector | Float32 256^3 | 7.049 ms | 7.041 ms | 7.017 ms | 7.149 ms | — |
| mean vector | Float32 64^3 | 41.924 μs | 42.695 μs | 41.196 μs | 40.899 μs | — |
| mean vector | Float64 128^3 | 1.425 ms | 1.416 ms | 1.390 ms | 1.420 ms | — |
| mean vector | Float64 256^3 | 14.046 ms | 14.033 ms | 14.065 ms | 14.203 ms | — |
| mean vector | Float64 64^3 | 79.681 μs | 79.960 μs | 80.916 μs | 81.131 μs | — |

