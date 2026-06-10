# Benchmark results

Minimum time per operation; `—` = not measured for that column. Generated 2026-06-10 at commit `4a49c0c` on Julia 1.12.6, host `Aiporetne`. Columns below are the runs supplied; grids and element types are in the row labels. The **CPU thread sweep 1/2/4/8 covers 64³–256³**. The **GPU column (RX 6700 XT, gfx1031, ROCm) shown here covers 64³–128³ for algebra/operators/transfer** — a pre-fix run; 256³ and the GPU `fft` class are obtainable but were not captured in this file. 256³ GPU FFT itself works fine; the only real limit is the 12 GB VRAM (the full suite for both element types at 256³ overflows it and HIP segfaults rather than erroring — PERFORMANCE.md §6 gap 5), which `characterize.jl` now avoids by building one (size, type) at a time. **Regenerate** the full column with `benchmark/characterize.sh` on a freshly-reset device. ~10% jitter.

## fft

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 4.998 ms | 3.291 ms | 2.395 ms | 2.276 ms | — |
| to_physical scalar | Float32 256^3 | 92.545 ms | 53.012 ms | 35.232 ms | 27.120 ms | — |
| to_physical scalar | Float32 64^3 | 388.019 μs | 251.009 μs | 169.639 μs | 153.777 μs | — |
| to_physical scalar | Float64 128^3 | 8.025 ms | 5.790 ms | 4.741 ms | 4.465 ms | — |
| to_physical scalar | Float64 256^3 | 98.067 ms | 65.205 ms | 79.733 ms | 74.518 ms | — |
| to_physical scalar | Float64 64^3 | 679.416 μs | 416.499 μs | 298.013 μs | 268.524 μs | — |
| to_physical vector | Float32 128^3 | 14.711 ms | 11.539 ms | 7.958 ms | 7.552 ms | — |
| to_physical vector | Float32 256^3 | 347.973 ms | 236.038 ms | 159.083 ms | 134.016 ms | — |
| to_physical vector | Float32 64^3 | 1.262 ms | 955.141 μs | 558.369 μs | 456.994 μs | — |
| to_physical vector | Float64 128^3 | 35.377 ms | 36.433 ms | 27.489 ms | 25.665 ms | — |
| to_physical vector | Float64 256^3 | 434.866 ms | 339.420 ms | 241.638 ms | 228.483 ms | — |
| to_physical vector | Float64 64^3 | 2.381 ms | 1.928 ms | 1.477 ms | 1.162 ms | — |
| to_spectral scalar | Float32 128^3 | 4.497 ms | 2.728 ms | 1.935 ms | 1.531 ms | — |
| to_spectral scalar | Float32 256^3 | 89.576 ms | 48.667 ms | 30.388 ms | 22.523 ms | — |
| to_spectral scalar | Float32 64^3 | 367.038 μs | 212.362 μs | 160.486 μs | 122.115 μs | — |
| to_spectral scalar | Float64 128^3 | 7.110 ms | 4.804 ms | 3.881 ms | 3.245 ms | — |
| to_spectral scalar | Float64 256^3 | 116.786 ms | 66.879 ms | 75.123 ms | 64.106 ms | — |
| to_spectral scalar | Float64 64^3 | 634.213 μs | 368.676 μs | 240.442 μs | 264.423 μs | — |
| to_spectral vector | Float32 128^3 | 13.465 ms | 9.979 ms | 6.485 ms | 5.758 ms | — |
| to_spectral vector | Float32 256^3 | 335.644 ms | 229.006 ms | 147.788 ms | 119.438 ms | — |
| to_spectral vector | Float32 64^3 | 1.183 ms | 844.489 μs | 453.906 μs | 370.332 μs | — |
| to_spectral vector | Float64 128^3 | 41.384 ms | 23.336 ms | 24.430 ms | 22.944 ms | — |
| to_spectral vector | Float64 256^3 | 489.445 ms | 367.222 ms | 233.029 ms | 201.902 ms | — |
| to_spectral vector | Float64 64^3 | 2.134 ms | 1.609 ms | 997.798 μs | 819.328 μs | — |

## algebra

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 410.015 μs | 3.668 ms | 1.877 ms | 945.061 μs | 117.948 μs |
| add! scalar | Float32 256^3 | 8.086 ms | 28.692 ms | 14.515 ms | 7.564 ms | — |
| add! scalar | Float32 64^3 | 42.390 μs | 453.834 μs | 232.088 μs | 121.493 μs | 30.492 μs |
| add! scalar | Float64 128^3 | 1.456 ms | 3.705 ms | 1.827 ms | 1.068 ms | 123.794 μs |
| add! scalar | Float64 256^3 | 16.873 ms | 29.087 ms | 16.902 ms | 14.400 ms | — |
| add! scalar | Float64 64^3 | 83.583 μs | 454.597 μs | 233.008 μs | 122.538 μs | 32.182 μs |
| cross! | Float32 128^3 | 4.464 ms | 16.554 ms | 8.526 ms | 4.375 ms | 443.206 μs |
| cross! | Float32 256^3 | 38.855 ms | 132.236 ms | 67.400 ms | 35.999 ms | — |
| cross! | Float32 64^3 | 421.468 μs | 2.050 ms | 1.033 ms | 539.297 μs | 77.905 μs |
| cross! | Float64 128^3 | 9.440 ms | 16.259 ms | 8.343 ms | 7.184 ms | 536.876 μs |
| cross! | Float64 256^3 | 83.539 ms | 132.992 ms | 77.697 ms | 67.569 ms | — |
| cross! | Float64 64^3 | 510.741 μs | 1.974 ms | 1.031 ms | 527.015 μs | 90.078 μs |
| dot! vec.vec | Float32 128^3 | 2.862 ms | 6.825 ms | 3.477 ms | 1.782 ms | 204.189 μs |
| dot! vec.vec | Float32 256^3 | 24.815 ms | 54.532 ms | 27.431 ms | 15.664 ms | — |
| dot! vec.vec | Float32 64^3 | 329.328 μs | 834.825 μs | 424.625 μs | 220.994 μs | 46.369 μs |
| dot! vec.vec | Float64 128^3 | 4.179 ms | 6.777 ms | 3.589 ms | 3.047 ms | 306.906 μs |
| dot! vec.vec | Float64 256^3 | 41.727 ms | 54.788 ms | 33.255 ms | 30.157 ms | — |
| dot! vec.vec | Float64 64^3 | 334.873 μs | 829.737 μs | 418.820 μs | 221.750 μs | 45.637 μs |
| mul! tensor.vec | Float32 128^3 | 9.169 ms | 20.900 ms | 10.552 ms | 5.535 ms | 608.646 μs |
| mul! tensor.vec | Float32 256^3 | 74.293 ms | 171.737 ms | 86.298 ms | 48.172 ms | — |
| mul! tensor.vec | Float32 64^3 | 1.099 ms | 2.575 ms | 1.344 ms | 680.513 μs | 102.801 μs |
| mul! tensor.vec | Float64 128^3 | 13.509 ms | 21.005 ms | 11.039 ms | 9.834 ms | 973.530 μs |
| mul! tensor.vec | Float64 256^3 | 114.695 ms | 169.861 ms | 100.921 ms | 91.074 ms | — |
| mul! tensor.vec | Float64 64^3 | 1.099 ms | 2.569 ms | 1.291 ms | 689.770 μs | 113.627 μs |
| norm! vec | Float32 128^3 | 721.696 μs | 5.001 ms | 2.521 ms | 1.277 ms | 141.816 μs |
| norm! vec | Float32 256^3 | 9.837 ms | 39.667 ms | 20.109 ms | 10.309 ms | — |
| norm! vec | Float32 64^3 | 53.512 μs | 609.321 μs | 306.316 μs | 160.704 μs | 35.481 μs |
| norm! vec | Float64 128^3 | 2.066 ms | 4.994 ms | 2.576 ms | 1.615 ms | 235.157 μs |
| norm! vec | Float64 256^3 | 21.220 ms | 40.629 ms | 21.224 ms | 18.783 ms | — |
| norm! vec | Float64 64^3 | 157.687 μs | 624.729 μs | 318.064 μs | 166.729 μs | 49.193 μs |

## operators

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.318 ms | 9.139 ms | 4.520 ms | 2.390 ms | 260.266 μs |
| curl! vec->vec | Float32 256^3 | 42.239 ms | 71.203 ms | 36.054 ms | 23.631 ms | — |
| curl! vec->vec | Float32 64^3 | 656.188 μs | 1.147 ms | 587.340 μs | 309.338 μs | 60.938 μs |
| curl! vec->vec | Float64 128^3 | 6.107 ms | 8.995 ms | 5.052 ms | 3.816 ms | 354.087 μs |
| curl! vec->vec | Float64 256^3 | 54.471 ms | 71.961 ms | 48.092 ms | 38.059 ms | — |
| curl! vec->vec | Float64 64^3 | 513.777 μs | 1.127 ms | 572.693 μs | 303.980 μs | 74.171 μs |
| divergence! vec->scalar | Float32 128^3 | 3.497 ms | 3.708 ms | 1.842 ms | 968.325 μs | 118.300 μs |
| divergence! vec->scalar | Float32 256^3 | 27.752 ms | 29.618 ms | 14.914 ms | 9.459 ms | — |
| divergence! vec->scalar | Float32 64^3 | 418.670 μs | 464.759 μs | 236.708 μs | 125.653 μs | 35.918 μs |
| divergence! vec->scalar | Float64 128^3 | 3.578 ms | 3.731 ms | 1.997 ms | 1.541 ms | 159.618 μs |
| divergence! vec->scalar | Float64 256^3 | 29.597 ms | 30.560 ms | 20.347 ms | 18.653 ms | — |
| divergence! vec->scalar | Float64 64^3 | 424.652 μs | 456.820 μs | 239.061 μs | 123.121 μs | 40.775 μs |
| gradient! scalar->vec | Float32 128^3 | 3.734 ms | 6.383 ms | 3.189 ms | 1.635 ms | 196.098 μs |
| gradient! scalar->vec | Float32 256^3 | 30.583 ms | 49.082 ms | 24.645 ms | 16.880 ms | — |
| gradient! scalar->vec | Float32 64^3 | 473.990 μs | 794.086 μs | 403.967 μs | 217.151 μs | 51.721 μs |
| gradient! scalar->vec | Float64 128^3 | 3.781 ms | 6.145 ms | 3.283 ms | 2.163 ms | 262.854 μs |
| gradient! scalar->vec | Float64 256^3 | 38.999 ms | 49.320 ms | 33.015 ms | 25.935 ms | — |
| gradient! scalar->vec | Float64 64^3 | 365.503 μs | 777.966 μs | 402.037 μs | 218.192 μs | 59.479 μs |
| helmholtz! vec->vec | Float32 128^3 | 7.178 ms | 11.170 ms | 7.597 ms | 6.470 ms | 470.107 μs |
| helmholtz! vec->vec | Float32 256^3 | 60.233 ms | 85.637 ms | 60.739 ms | 55.839 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 815.943 μs | 1.374 ms | 945.220 μs | 778.190 μs | 100.943 μs |
| helmholtz! vec->vec | Float64 128^3 | 11.555 ms | 13.073 ms | 10.206 ms | 9.630 ms | 607.478 μs |
| helmholtz! vec->vec | Float64 256^3 | 94.856 ms | 139.032 ms | 113.415 ms | 104.290 ms | — |
| helmholtz! vec->vec | Float64 64^3 | 995.126 μs | 1.572 ms | 1.099 ms | 906.650 μs | 115.362 μs |
| laplacian! scalar | Float32 128^3 | 1.921 ms | 2.629 ms | 1.555 ms | 1.089 ms | 197.222 μs |
| laplacian! scalar | Float32 256^3 | 16.037 ms | 20.388 ms | 13.878 ms | 12.043 ms | — |
| laplacian! scalar | Float32 64^3 | 199.125 μs | 268.303 μs | 166.055 μs | 120.384 μs | 53.846 μs |
| laplacian! scalar | Float64 128^3 | 3.086 ms | 3.569 ms | 2.811 ms | 2.400 ms | 203.335 μs |
| laplacian! scalar | Float64 256^3 | 26.871 ms | 30.246 ms | 24.401 ms | 21.694 ms | — |
| laplacian! scalar | Float64 64^3 | 246.148 μs | 330.555 μs | 216.635 μs | 179.876 μs | 53.253 μs |

## transfer

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.494 ms | 13.746 ms | 7.276 ms | 4.375 ms | 648.242 μs |
| anterpolate! CatmullRom | Float32 256^3 | 388.884 ms | 204.334 ms | 109.394 ms | 69.332 ms | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.182 ms | 1.839 ms | 1.196 ms | 853.264 μs | 139.706 μs |
| anterpolate! CatmullRom | Float64 128^3 | 29.630 ms | 14.865 ms | 7.635 ms | 4.629 ms | 662.464 μs |
| anterpolate! CatmullRom | Float64 256^3 | 490.916 ms | 260.064 ms | 146.472 ms | 102.920 ms | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.322 ms | 1.912 ms | 1.238 ms | 904.341 μs | 134.213 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 197.792 ms | 100.063 ms | 50.965 ms | 28.500 ms | 4.862 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.234 s | 1.167 s | 670.969 ms | 484.173 ms | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.901 ms | 13.254 ms | 8.201 ms | 5.750 ms | 841.381 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 208.675 ms | 104.952 ms | 52.712 ms | 29.815 ms | 4.571 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.566 s | 1.421 s | 860.024 ms | 617.658 ms | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.350 ms | 13.411 ms | 8.222 ms | 5.638 ms | 799.775 μs |
| anterpolate! trilinear | Float32 128^3 | 4.645 ms | 2.324 ms | 1.314 ms | 864.391 μs | 131.059 μs |
| anterpolate! trilinear | Float32 256^3 | 80.723 ms | 44.377 ms | 25.745 ms | 16.880 ms | — |
| anterpolate! trilinear | Float32 64^3 | 483.893 μs | 307.199 μs | 215.764 μs | 169.784 μs | 38.578 μs |
| anterpolate! trilinear | Float64 128^3 | 5.445 ms | 2.836 ms | 1.549 ms | 1.089 ms | 145.158 μs |
| anterpolate! trilinear | Float64 256^3 | 90.378 ms | 51.375 ms | 33.101 ms | 27.028 ms | — |
| anterpolate! trilinear | Float64 64^3 | 513.739 μs | 337.029 μs | 239.436 μs | 191.679 μs | 41.897 μs |
| interpolate! CatmullRom | Float32 128^3 | 11.516 ms | 5.887 ms | 3.005 ms | 1.620 ms | 333.061 μs |
| interpolate! CatmullRom | Float32 256^3 | 264.605 ms | 139.688 ms | 75.426 ms | 45.444 ms | — |
| interpolate! CatmullRom | Float32 64^3 | 1.310 ms | 710.626 μs | 434.483 μs | 299.804 μs | 77.194 μs |
| interpolate! CatmullRom | Float64 128^3 | 13.842 ms | 7.069 ms | 3.518 ms | 1.938 ms | 269.960 μs |
| interpolate! CatmullRom | Float64 256^3 | 293.183 ms | 154.390 ms | 87.025 ms | 59.901 ms | — |
| interpolate! CatmullRom | Float64 64^3 | 1.361 ms | 737.605 μs | 450.021 μs | 314.809 μs | 75.316 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.550 ms | 37.311 ms | 19.024 ms | 10.493 ms | 2.436 ms |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.387 s | 783.663 ms | 500.477 ms | 323.888 ms | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.739 ms | 4.712 ms | 2.832 ms | 1.941 ms | 350.313 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 85.421 ms | 43.358 ms | 21.710 ms | 12.200 ms | 1.560 ms |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.761 s | 992.598 ms | 653.286 ms | 436.387 ms | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.947 ms | 4.821 ms | 2.967 ms | 2.008 ms | 434.297 μs |
| interpolate! trilinear | Float32 128^3 | 1.998 ms | 1.023 ms | 529.906 μs | 291.060 μs | 50.651 μs |
| interpolate! trilinear | Float32 256^3 | 54.221 ms | 28.014 ms | 15.378 ms | 9.041 ms | — |
| interpolate! trilinear | Float32 64^3 | 225.842 μs | 124.938 μs | 77.724 μs | 56.022 μs | 26.006 μs |
| interpolate! trilinear | Float64 128^3 | 2.590 ms | 1.292 ms | 634.490 μs | 370.129 μs | 65.013 μs |
| interpolate! trilinear | Float64 256^3 | 58.358 ms | 32.060 ms | 18.949 ms | 13.375 ms | — |
| interpolate! trilinear | Float64 64^3 | 237.887 μs | 134.508 μs | 81.423 μs | 58.464 μs | 30.834 μs |

