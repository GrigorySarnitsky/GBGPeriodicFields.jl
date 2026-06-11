# Benchmark results

Minimum time per operation; `—` = not measured for that column. Generated 2026-06-11 at commit `5069e3b` on Julia 1.12.6, host `Aiporetne`. Columns below are the runs supplied; grids and element types are in the row labels. The **CPU thread sweep 1/2/4/8 and the GPU (RX 6700 XT, gfx1031, ROCm) all cover 64³–256³, every op-class incl. FFT.** The GPU sweep builds one (op-class, grid, element-type) at a time so the 256³ working set fits in 12 GB VRAM (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh`. ~10% jitter.

## fft

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 4.885 ms | 3.207 ms | 2.303 ms | 1.944 ms | 2.496 ms |
| to_physical scalar | Float32 256^3 | 115.106 ms | 70.332 ms | 48.509 ms | 40.307 ms | 7.905 ms |
| to_physical scalar | Float32 64^3 | 386.223 μs | 246.264 μs | 167.042 μs | 144.503 μs | 1.469 ms |
| to_physical scalar | Float64 128^3 | 7.982 ms | 5.929 ms | 4.747 ms | 4.378 ms | 3.647 ms |
| to_physical scalar | Float64 256^3 | 145.459 ms | 97.665 ms | 79.015 ms | 73.868 ms | 13.532 ms |
| to_physical scalar | Float64 64^3 | 682.471 μs | 405.133 μs | 290.586 μs | 258.343 μs | 1.916 ms |
| to_physical vector | Float32 128^3 | 14.863 ms | 11.377 ms | 8.069 ms | 7.381 ms | 4.613 ms |
| to_physical vector | Float32 256^3 | 349.831 ms | 256.849 ms | 163.713 ms | 138.921 ms | 15.539 ms |
| to_physical vector | Float32 64^3 | 1.282 ms | 962.956 μs | 519.176 μs | 450.601 μs | 1.901 ms |
| to_physical vector | Float64 128^3 | 35.483 ms | 36.237 ms | 26.955 ms | 26.298 ms | 8.033 ms |
| to_physical vector | Float64 256^3 | 437.187 ms | 336.559 ms | 241.514 ms | 228.971 ms | 22.987 ms |
| to_physical vector | Float64 64^3 | 2.553 ms | 1.998 ms | 1.310 ms | 1.306 ms | 2.329 ms |
| to_spectral scalar | Float32 128^3 | 4.340 ms | 2.649 ms | 1.653 ms | 1.259 ms | 2.102 ms |
| to_spectral scalar | Float32 256^3 | 113.092 ms | 67.412 ms | 45.385 ms | 35.559 ms | 4.949 ms |
| to_spectral scalar | Float32 64^3 | 365.945 μs | 207.071 μs | 125.507 μs | 101.351 μs | 1.514 ms |
| to_spectral scalar | Float64 128^3 | 7.114 ms | 5.236 ms | 3.943 ms | 3.358 ms | 3.057 ms |
| to_spectral scalar | Float64 256^3 | 163.533 ms | 103.629 ms | 74.136 ms | 63.181 ms | 14.078 ms |
| to_spectral scalar | Float64 64^3 | 637.761 μs | 357.949 μs | 222.669 μs | 179.301 μs | 1.767 ms |
| to_spectral vector | Float32 128^3 | 13.396 ms | 9.856 ms | 6.685 ms | 5.886 ms | 3.213 ms |
| to_spectral vector | Float32 256^3 | 338.198 ms | 247.605 ms | 148.167 ms | 119.739 ms | 11.822 ms |
| to_spectral vector | Float32 64^3 | 1.189 ms | 861.857 μs | 403.116 μs | 326.883 μs | 1.446 ms |
| to_spectral vector | Float64 128^3 | 32.305 ms | 33.509 ms | 13.702 ms | 12.387 ms | 6.525 ms |
| to_spectral vector | Float64 256^3 | 486.156 ms | 366.080 ms | 230.453 ms | 202.012 ms | 20.912 ms |
| to_spectral vector | Float64 64^3 | 2.342 ms | 1.610 ms | 1.179 ms | 792.661 μs | 2.182 ms |

## algebra

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 401.856 μs | 3.589 ms | 1.799 ms | 944.510 μs | 2.025 ms |
| add! scalar | Float32 256^3 | 8.064 ms | 28.685 ms | 14.659 ms | 7.672 ms | 5.428 ms |
| add! scalar | Float32 64^3 | 42.274 μs | 451.810 μs | 231.402 μs | 121.224 μs | 1.588 ms |
| add! scalar | Float64 128^3 | 1.466 ms | 3.633 ms | 1.856 ms | 1.076 ms | 2.175 ms |
| add! scalar | Float64 256^3 | 16.714 ms | 29.061 ms | 17.294 ms | 14.756 ms | 5.559 ms |
| add! scalar | Float64 64^3 | 83.818 μs | 454.800 μs | 235.910 μs | 121.865 μs | 1.546 ms |
| cross! | Float32 128^3 | 4.634 ms | 16.568 ms | 8.344 ms | 4.390 ms | 3.558 ms |
| cross! | Float32 256^3 | 42.332 ms | 133.586 ms | 68.025 ms | 35.468 ms | 14.495 ms |
| cross! | Float32 64^3 | 498.368 μs | 2.048 ms | 1.059 ms | 543.350 μs | 1.842 ms |
| cross! | Float64 128^3 | 9.491 ms | 16.384 ms | 8.483 ms | 7.128 ms | 3.709 ms |
| cross! | Float64 256^3 | 77.591 ms | 131.483 ms | 74.624 ms | 66.996 ms | 15.268 ms |
| cross! | Float64 64^3 | 510.588 μs | 1.972 ms | 1.002 ms | 526.510 μs | 1.813 ms |
| dot! vec.vec | Float32 128^3 | 2.809 ms | 6.787 ms | 3.411 ms | 1.783 ms | 2.338 ms |
| dot! vec.vec | Float32 256^3 | 24.209 ms | 54.162 ms | 27.285 ms | 15.305 ms | 8.752 ms |
| dot! vec.vec | Float32 64^3 | 328.396 μs | 838.411 μs | 430.364 μs | 221.435 μs | 1.588 ms |
| dot! vec.vec | Float64 128^3 | 4.467 ms | 6.906 ms | 3.622 ms | 2.992 ms | 2.552 ms |
| dot! vec.vec | Float64 256^3 | 36.131 ms | 54.761 ms | 33.186 ms | 29.793 ms | 9.650 ms |
| dot! vec.vec | Float64 64^3 | 335.293 μs | 830.538 μs | 420.111 μs | 221.601 μs | 1.648 ms |
| mul! tensor.vec | Float32 128^3 | 8.733 ms | 21.181 ms | 10.542 ms | 5.559 ms | 4.360 ms |
| mul! tensor.vec | Float32 256^3 | 74.685 ms | 170.431 ms | 84.503 ms | 48.841 ms | 16.142 ms |
| mul! tensor.vec | Float32 64^3 | 991.038 μs | 2.587 ms | 1.328 ms | 684.388 μs | 1.826 ms |
| mul! tensor.vec | Float64 128^3 | 14.115 ms | 21.080 ms | 11.117 ms | 10.123 ms | 4.832 ms |
| mul! tensor.vec | Float64 256^3 | 109.183 ms | 168.985 ms | 100.849 ms | 91.199 ms | 16.940 ms |
| mul! tensor.vec | Float64 64^3 | 1.067 ms | 2.562 ms | 1.317 ms | 683.736 μs | 1.993 ms |
| norm! vec | Float32 128^3 | 723.427 μs | 4.987 ms | 2.518 ms | 1.288 ms | 2.124 ms |
| norm! vec | Float32 256^3 | 10.283 ms | 39.705 ms | 19.817 ms | 10.405 ms | 6.310 ms |
| norm! vec | Float32 64^3 | 53.534 μs | 607.847 μs | 313.455 μs | 161.360 μs | 346.931 μs |
| norm! vec | Float64 128^3 | 2.104 ms | 5.046 ms | 2.517 ms | 1.611 ms | 2.587 ms |
| norm! vec | Float64 256^3 | 20.655 ms | 40.786 ms | 21.208 ms | 18.780 ms | 9.895 ms |
| norm! vec | Float64 64^3 | 157.686 μs | 626.671 μs | 326.757 μs | 166.755 μs | 1.611 ms |

## operators

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.367 ms | 8.912 ms | 4.482 ms | 2.374 ms | 2.519 ms |
| curl! vec->vec | Float32 256^3 | 42.622 ms | 71.204 ms | 36.619 ms | 23.817 ms | 10.165 ms |
| curl! vec->vec | Float32 64^3 | 656.205 μs | 1.159 ms | 586.863 μs | 310.844 μs | 1.754 ms |
| curl! vec->vec | Float64 128^3 | 6.172 ms | 8.940 ms | 5.092 ms | 3.864 ms | 3.083 ms |
| curl! vec->vec | Float64 256^3 | 54.814 ms | 72.106 ms | 48.042 ms | 38.335 ms | 13.777 ms |
| curl! vec->vec | Float64 64^3 | 514.344 μs | 1.136 ms | 572.903 μs | 304.179 μs | 1.678 ms |
| divergence! vec->scalar | Float32 128^3 | 3.533 ms | 3.642 ms | 1.828 ms | 972.702 μs | 2.012 ms |
| divergence! vec->scalar | Float32 256^3 | 27.994 ms | 29.507 ms | 14.851 ms | 9.112 ms | 5.515 ms |
| divergence! vec->scalar | Float32 64^3 | 441.343 μs | 463.437 μs | 236.483 μs | 125.630 μs | 1.490 ms |
| divergence! vec->scalar | Float64 128^3 | 3.694 ms | 3.663 ms | 1.974 ms | 1.617 ms | 2.284 ms |
| divergence! vec->scalar | Float64 256^3 | 31.518 ms | 30.609 ms | 20.377 ms | 18.623 ms | 7.112 ms |
| divergence! vec->scalar | Float64 64^3 | 433.062 μs | 461.240 μs | 233.214 μs | 125.061 μs | 1.501 ms |
| gradient! scalar->vec | Float32 128^3 | 3.735 ms | 6.189 ms | 3.178 ms | 1.637 ms | 2.208 ms |
| gradient! scalar->vec | Float32 256^3 | 30.584 ms | 49.065 ms | 24.605 ms | 16.548 ms | 7.737 ms |
| gradient! scalar->vec | Float32 64^3 | 474.060 μs | 791.319 μs | 402.922 μs | 218.202 μs | 1.683 ms |
| gradient! scalar->vec | Float64 128^3 | 3.805 ms | 6.100 ms | 3.301 ms | 2.255 ms | 2.697 ms |
| gradient! scalar->vec | Float64 256^3 | 38.906 ms | 49.034 ms | 33.689 ms | 24.201 ms | 10.338 ms |
| gradient! scalar->vec | Float64 64^3 | 365.456 μs | 773.090 μs | 400.705 μs | 216.368 μs | 1.664 ms |
| helmholtz! vec->vec | Float32 128^3 | 7.348 ms | 10.765 ms | 7.534 ms | 6.630 ms | 3.516 ms |
| helmholtz! vec->vec | Float32 256^3 | 78.252 ms | 110.530 ms | 79.180 ms | 77.233 ms | 14.424 ms |
| helmholtz! vec->vec | Float32 64^3 | 815.300 μs | 1.388 ms | 961.859 μs | 799.378 μs | 1.850 ms |
| helmholtz! vec->vec | Float64 128^3 | 11.519 ms | 12.560 ms | 10.074 ms | 9.566 ms | 4.157 ms |
| helmholtz! vec->vec | Float64 256^3 | 137.089 ms | 142.935 ms | 128.151 ms | 121.692 ms | 16.434 ms |
| helmholtz! vec->vec | Float64 64^3 | 986.737 μs | 1.522 ms | 1.086 ms | 894.042 μs | 1.906 ms |
| laplacian! scalar | Float32 128^3 | 1.885 ms | 2.455 ms | 1.591 ms | 1.064 ms | 2.275 ms |
| laplacian! scalar | Float32 256^3 | 20.330 ms | 29.086 ms | 18.208 ms | 21.088 ms | 7.654 ms |
| laplacian! scalar | Float32 64^3 | 198.755 μs | 271.703 μs | 160.353 μs | 118.461 μs | 1.717 ms |
| laplacian! scalar | Float64 128^3 | 2.917 ms | 3.306 ms | 2.620 ms | 2.427 ms | 2.552 ms |
| laplacian! scalar | Float64 256^3 | 43.621 ms | 45.245 ms | 41.250 ms | 38.395 ms | 8.123 ms |
| laplacian! scalar | Float64 64^3 | 239.559 μs | 322.649 μs | 203.729 μs | 159.946 μs | 1.704 ms |

## convolution

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| convolve! scalar | Float32 128^3 | 1.604 ms | 2.091 ms | 1.037 ms | 542.939 μs | 1.852 ms |
| convolve! scalar | Float32 256^3 | 13.207 ms | 16.359 ms | 8.293 ms | 6.847 ms | 3.690 ms |
| convolve! scalar | Float32 64^3 | 197.654 μs | 262.223 μs | 134.225 μs | 71.860 μs | 1.574 ms |
| convolve! scalar | Float64 128^3 | 1.761 ms | 2.095 ms | 1.260 ms | 922.954 μs | 1.888 ms |
| convolve! scalar | Float64 256^3 | 17.907 ms | 17.293 ms | 13.693 ms | 11.277 ms | 4.402 ms |
| convolve! scalar | Float64 64^3 | 176.219 μs | 258.193 μs | 131.604 μs | 70.980 μs | 1.521 ms |
| convolve! vector | Float32 128^3 | 5.880 ms | 9.023 ms | 4.566 ms | 2.359 ms | 2.529 ms |
| convolve! vector | Float32 256^3 | 47.347 ms | 70.942 ms | 35.705 ms | 21.956 ms | 9.768 ms |
| convolve! vector | Float32 64^3 | 719.189 μs | 1.143 ms | 571.233 μs | 299.488 μs | 1.651 ms |
| convolve! vector | Float64 128^3 | 6.409 ms | 9.117 ms | 4.960 ms | 3.773 ms | 2.844 ms |
| convolve! vector | Float64 256^3 | 56.637 ms | 73.141 ms | 45.395 ms | 38.933 ms | 12.327 ms |
| convolve! vector | Float64 64^3 | 688.080 μs | 1.149 ms | 576.973 μs | 303.575 μs | 1.734 ms |
| spectral_cutoff | Float32 128^3 | 1.296 ms | 1.826 ms | 1.047 ms | 700.858 μs | 2.053 ms |
| spectral_cutoff | Float32 256^3 | 22.504 ms | 25.247 ms | 12.036 ms | 12.260 ms | 5.645 ms |
| spectral_cutoff | Float32 64^3 | 143.721 μs | 213.591 μs | 121.755 μs | 87.113 μs | 1.612 ms |
| spectral_cutoff | Float64 128^3 | 1.747 ms | 2.132 ms | 1.642 ms | 1.424 ms | 2.091 ms |
| spectral_cutoff | Float64 256^3 | 46.682 ms | 38.981 ms | 26.786 ms | 21.602 ms | 5.969 ms |
| spectral_cutoff | Float64 64^3 | 162.205 μs | 249.827 μs | 144.171 μs | 136.214 μs | 1.618 ms |

## transfer

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 27.494 ms | 13.833 ms | 7.344 ms | 4.421 ms | 4.988 ms |
| anterpolate! CatmullRom | Float32 256^3 | 386.455 ms | 202.263 ms | 109.379 ms | 67.595 ms | 16.382 ms |
| anterpolate! CatmullRom | Float32 64^3 | 3.164 ms | 1.837 ms | 1.200 ms | 867.320 μs | 2.147 ms |
| anterpolate! CatmullRom | Float64 128^3 | 29.090 ms | 14.802 ms | 7.713 ms | 4.598 ms | 5.037 ms |
| anterpolate! CatmullRom | Float64 256^3 | 497.789 ms | 265.582 ms | 149.200 ms | 103.133 ms | 17.617 ms |
| anterpolate! CatmullRom | Float64 64^3 | 3.325 ms | 1.908 ms | 1.240 ms | 903.137 μs | 2.085 ms |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 197.511 ms | 100.238 ms | 50.792 ms | 28.628 ms | 16.484 ms |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.207 s | 1.161 s | 675.521 ms | 481.064 ms | 48.293 ms |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.814 ms | 13.115 ms | 8.210 ms | 5.735 ms | 6.079 ms |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 206.609 ms | 104.972 ms | 52.586 ms | 29.730 ms | 15.391 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.578 s | 1.414 s | 845.714 ms | 637.272 ms | 64.720 ms |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.301 ms | 13.249 ms | 8.243 ms | 5.726 ms | 5.598 ms |
| anterpolate! trilinear | Float32 128^3 | 4.639 ms | 2.263 ms | 1.340 ms | 874.240 μs | 2.053 ms |
| anterpolate! trilinear | Float32 256^3 | 80.692 ms | 44.369 ms | 26.007 ms | 19.261 ms | 5.730 ms |
| anterpolate! trilinear | Float32 64^3 | 481.100 μs | 305.444 μs | 215.276 μs | 161.166 μs | 1.649 ms |
| anterpolate! trilinear | Float64 128^3 | 5.253 ms | 2.692 ms | 1.549 ms | 1.078 ms | 1.879 ms |
| anterpolate! trilinear | Float64 256^3 | 90.708 ms | 52.132 ms | 33.647 ms | 27.010 ms | 5.432 ms |
| anterpolate! trilinear | Float64 64^3 | 513.628 μs | 337.225 μs | 241.921 μs | 192.843 μs | 1.598 ms |
| interpolate! CatmullRom | Float32 128^3 | 11.526 ms | 5.842 ms | 2.980 ms | 1.630 ms | 3.046 ms |
| interpolate! CatmullRom | Float32 256^3 | 266.322 ms | 139.467 ms | 76.072 ms | 46.778 ms | 13.645 ms |
| interpolate! CatmullRom | Float32 64^3 | 1.303 ms | 710.846 μs | 434.431 μs | 299.269 μs | 1.747 ms |
| interpolate! CatmullRom | Float64 128^3 | 13.135 ms | 7.044 ms | 3.483 ms | 1.895 ms | 2.787 ms |
| interpolate! CatmullRom | Float64 256^3 | 297.762 ms | 160.528 ms | 90.381 ms | 60.250 ms | 11.407 ms |
| interpolate! CatmullRom | Float64 64^3 | 1.361 ms | 737.107 μs | 451.229 μs | 314.620 μs | 1.815 ms |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.493 ms | 37.368 ms | 18.898 ms | 10.414 ms | 13.553 ms |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.414 s | 774.065 ms | 502.490 ms | 325.394 ms | 29.732 ms |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.704 ms | 4.718 ms | 2.878 ms | 1.940 ms | 3.193 ms |
| interpolate! Lalescu(3,3) | Float64 128^3 | 83.081 ms | 44.375 ms | 21.506 ms | 11.872 ms | 9.447 ms |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.787 s | 1.030 s | 654.232 ms | 438.347 ms | 26.052 ms |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.943 ms | 4.818 ms | 2.970 ms | 2.006 ms | 3.503 ms |
| interpolate! trilinear | Float32 128^3 | 2.006 ms | 1.018 ms | 519.588 μs | 287.550 μs | 1.757 ms |
| interpolate! trilinear | Float32 256^3 | 53.491 ms | 28.452 ms | 15.560 ms | 8.949 ms | 2.717 ms |
| interpolate! trilinear | Float32 64^3 | 223.941 μs | 127.088 μs | 77.977 μs | 55.556 μs | 1.493 ms |
| interpolate! trilinear | Float64 128^3 | 2.342 ms | 1.267 ms | 633.597 μs | 358.771 μs | 1.732 ms |
| interpolate! trilinear | Float64 256^3 | 58.805 ms | 33.266 ms | 20.416 ms | 13.416 ms | 3.194 ms |
| interpolate! trilinear | Float64 64^3 | 238.858 μs | 132.634 μs | 81.679 μs | 57.704 μs | 1.513 ms |

## reductions

| operation | CPU t1 | CPU t2 | CPU t4 | CPU t8 | GPU |
|:--|:--|:--|:--|:--|:--|
| inner vec.vec | Float32 128^3 | 1.237 ms | 1.306 ms | 1.304 ms | 1.221 ms | 1.622 ms |
| inner vec.vec | Float32 256^3 | 12.688 ms | 12.503 ms | 12.501 ms | 12.503 ms | 3.425 ms |
| inner vec.vec | Float32 64^3 | 64.828 μs | 65.888 μs | 64.712 μs | 65.377 μs | 1.393 ms |
| inner vec.vec | Float64 128^3 | 2.175 ms | 2.193 ms | 2.181 ms | 2.188 ms | 1.900 ms |
| inner vec.vec | Float64 256^3 | 22.171 ms | 22.188 ms | 22.164 ms | 22.170 ms | 5.626 ms |
| inner vec.vec | Float64 64^3 | 33.640 μs | 31.225 μs | 34.023 μs | 33.681 μs | 1.430 ms |
| integral scalar | Float32 128^3 | 108.683 μs | 111.646 μs | 106.915 μs | 111.397 μs | 2.363 ms |
| integral scalar | Float32 256^3 | 2.041 ms | 2.444 ms | 2.470 ms | 2.316 ms | 9.038 ms |
| integral scalar | Float32 64^3 | 10.515 μs | 10.255 μs | 10.279 μs | 10.010 μs | 1.602 ms |
| integral scalar | Float64 128^3 | 235.830 μs | 232.528 μs | 245.343 μs | 235.813 μs | 2.549 ms |
| integral scalar | Float64 256^3 | 4.876 ms | 4.467 ms | 5.104 ms | 4.559 ms | 10.009 ms |
| integral scalar | Float64 64^3 | 26.263 μs | 25.891 μs | 26.239 μs | 26.515 μs | 1.608 ms |
| l2norm vec | Float32 128^3 | 521.112 μs | 527.613 μs | 533.675 μs | 484.663 μs | 1.566 ms |
| l2norm vec | Float32 256^3 | 6.941 ms | 6.637 ms | 6.600 ms | 6.631 ms | 3.304 ms |
| l2norm vec | Float32 64^3 | 39.712 μs | 39.515 μs | 39.609 μs | 39.776 μs | 1.423 ms |
| l2norm vec | Float64 128^3 | 731.735 μs | 738.400 μs | 732.750 μs | 734.659 μs | 1.910 ms |
| l2norm vec | Float64 256^3 | 11.056 ms | 11.148 ms | 11.060 ms | 11.181 ms | 5.537 ms |
| l2norm vec | Float64 64^3 | 16.618 μs | 11.205 μs | 16.259 μs | 16.363 μs | 1.377 ms |
| lpnorm vec Inf | Float32 128^3 | 1.354 ms | 5.399 ms | 3.022 ms | 1.801 ms | 2.979 ms |
| lpnorm vec Inf | Float32 256^3 | 21.852 ms | 50.031 ms | 26.483 ms | 15.319 ms | 13.396 ms |
| lpnorm vec Inf | Float32 64^3 | 96.280 μs | 657.446 μs | 358.729 μs | 216.857 μs | 1.618 ms |
| lpnorm vec Inf | Float64 128^3 | 3.089 ms | 6.392 ms | 3.623 ms | 2.995 ms | 3.782 ms |
| lpnorm vec Inf | Float64 256^3 | 44.757 ms | 59.642 ms | 33.823 ms | 22.241 ms | 14.670 ms |
| lpnorm vec Inf | Float64 64^3 | 231.300 μs | 747.184 μs | 438.545 μs | 268.052 μs | 1.839 ms |
| maximum scalar | Float32 128^3 | 334.489 μs | 336.208 μs | 334.649 μs | 336.880 μs | 2.420 ms |
| maximum scalar | Float32 256^3 | 2.878 ms | 3.269 ms | 3.318 ms | 3.147 ms | 9.106 ms |
| maximum scalar | Float32 64^3 | 41.712 μs | 41.749 μs | 41.754 μs | 41.786 μs | 1.604 ms |
| maximum scalar | Float64 128^3 | 541.294 μs | 538.077 μs | 555.552 μs | 545.031 μs | 2.744 ms |
| maximum scalar | Float64 256^3 | 6.425 ms | 6.038 ms | 6.784 ms | 6.141 ms | 11.892 ms |
| maximum scalar | Float64 64^3 | 65.236 μs | 65.017 μs | 65.130 μs | 65.324 μs | 1.649 ms |
| mean vector | Float32 128^3 | 545.453 μs | 533.008 μs | 563.838 μs | 514.852 μs | 4.773 ms |
| mean vector | Float32 256^3 | 7.461 ms | 7.148 ms | 7.135 ms | 7.152 ms | 16.321 ms |
| mean vector | Float32 64^3 | 40.989 μs | 40.784 μs | 40.622 μs | 41.067 μs | 1.928 ms |
| mean vector | Float64 128^3 | 1.444 ms | 1.512 ms | 1.406 ms | 1.599 ms | 5.131 ms |
| mean vector | Float64 256^3 | 13.916 ms | 14.315 ms | 14.011 ms | 14.459 ms | 17.050 ms |
| mean vector | Float64 64^3 | 81.821 μs | 79.733 μs | 80.675 μs | 80.597 μs | 1.908 ms |

