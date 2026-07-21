# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-07-21 at commit `0cf2cb0` on Julia 1.12.6, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–256³) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB). Read any CPU t2–t8 column against PERFORMANCE.md §4 finding (l): the threaded `_assign!` inner loop runs ~8.6 GB/s per thread, so mid thread counts can sit *above* t1 on the streaming ops. **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh` plus the per-card / per-CPU archive in `benchmark/results/` (PERFORMANCE.md §6). ~10% jitter.

## fft

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar | Float32 128^3 | 5.185 ms | 3.332 ms | 2.425 ms | 2.386 ms | 4.729 ms | 2.466 ms | 1.285 ms | 759.128 μs | 788.067 μs | 2.421 ms | 435.844 μs | 117.831 μs |
| to_physical scalar | Float32 256^3 | 120.456 ms | 75.085 ms | 39.701 ms | 37.317 ms | 181.899 ms | 99.684 ms | 56.005 ms | 35.477 ms | — | 7.945 ms | 1.492 ms | 1.077 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | 2.114 s | 1.119 s | 632.070 ms | 402.297 ms | — | — | — | — |
| to_physical scalar | Float32 64^3 | 404.712 μs | 256.238 μs | 172.228 μs | 141.909 μs | 315.491 μs | 177.652 μs | 101.751 μs | 71.191 μs | 124.402 μs | 1.497 ms | 335.253 μs | 102.161 μs |
| to_physical scalar | Float64 128^3 | 8.342 ms | 5.868 ms | 5.057 ms | 4.609 ms | 10.039 ms | 5.587 ms | 2.924 ms | 1.720 ms | 1.905 ms | 3.750 ms | 904.753 μs | 490.495 μs |
| to_physical scalar | Float64 256^3 | 154.523 ms | 104.915 ms | 86.850 ms | 81.789 ms | 116.024 ms | 74.516 ms | 53.709 ms | 45.354 ms | — | 14.463 ms | 5.261 ms | 3.819 ms |
| to_physical scalar | Float64 512^3 | — | — | — | — | 945.503 ms | 604.897 ms | 456.454 ms | 402.195 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 699.028 μs | 443.724 μs | 318.737 μs | 267.959 μs | 525.746 μs | 289.483 μs | 164.951 μs | 113.831 μs | 331.873 μs | 1.784 ms | 392.529 μs | 131.461 μs |
| to_physical vector | Float32 128^3 | 15.516 ms | 11.976 ms | 8.329 ms | 8.304 ms | 14.510 ms | 10.212 ms | 5.458 ms | 3.691 ms | 2.507 ms | 4.595 ms | 826.947 μs | 298.423 μs |
| to_physical vector | Float32 256^3 | 376.172 ms | 273.666 ms | 172.548 ms | 146.567 ms | 587.912 ms | 409.111 ms | 218.952 ms | 160.916 ms | — | 14.844 ms | 5.000 ms | 3.475 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | 6.327 s | 4.311 s | 2.296 s | 1.652 s | — | — | — | — |
| to_physical vector | Float32 64^3 | 1.327 ms | 997.886 μs | 541.102 μs | 501.331 μs | 988.143 μs | 683.258 μs | 314.293 μs | 210.052 μs | 380.054 μs | 1.776 ms | 359.155 μs | 122.332 μs |
| to_physical vector | Float64 128^3 | 38.026 ms | 31.968 ms | 20.850 ms | 19.459 ms | 41.723 ms | 28.717 ms | 20.277 ms | 15.716 ms | 5.630 ms | 8.090 ms | 2.173 ms | 1.454 ms |
| to_physical vector | Float64 256^3 | 465.868 ms | 359.990 ms | 258.848 ms | 247.224 ms | 362.012 ms | 269.624 ms | 174.633 ms | 155.875 ms | — | 22.812 ms | 13.079 ms | 11.323 ms |
| to_physical vector | Float64 512^3 | — | — | — | — | 2.805 s | 2.133 s | 1.404 s | 1.246 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.791 ms | 2.220 ms | 1.596 ms | 1.213 ms | 1.638 ms | 1.088 ms | 563.564 μs | 416.034 μs | 811.437 μs | 2.301 ms | 618.297 μs | 220.243 μs |
| to_spectral scalar | Float32 128^3 | 4.656 ms | 2.812 ms | 1.691 ms | 1.605 ms | 4.608 ms | 2.455 ms | 1.266 ms | 710.828 μs | 488.254 μs | 2.072 ms | 358.889 μs | 94.121 μs |
| to_spectral scalar | Float32 256^3 | 118.430 ms | 71.360 ms | 36.322 ms | 26.415 ms | 185.486 ms | 99.803 ms | 56.484 ms | 34.837 ms | — | 5.009 ms | 991.167 μs | 729.638 μs |
| to_spectral scalar | Float32 512^3 | — | — | — | — | 2.092 s | 1.106 s | 604.661 ms | 375.422 ms | — | — | — | — |
| to_spectral scalar | Float32 64^3 | 383.004 μs | 218.234 μs | 132.117 μs | 114.514 μs | 306.192 μs | 166.862 μs | 91.341 μs | 58.731 μs | 89.181 μs | 1.538 ms | 355.056 μs | 68.810 μs |
| to_spectral scalar | Float64 128^3 | 7.445 ms | 5.217 ms | 4.181 ms | 3.436 ms | 9.980 ms | 5.547 ms | 2.980 ms | 1.683 ms | 1.501 ms | 3.125 ms | 826.771 μs | 423.674 μs |
| to_spectral scalar | Float64 256^3 | 173.710 ms | 109.655 ms | 80.023 ms | 68.113 ms | 208.452 ms | 117.240 ms | 73.054 ms | 51.911 ms | — | 12.871 ms | 4.227 ms | 3.109 ms |
| to_spectral scalar | Float64 512^3 | — | — | — | — | 1.738 s | 975.117 ms | 591.402 ms | 429.637 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 697.766 μs | 371.362 μs | 245.627 μs | 177.574 μs | 508.725 μs | 273.104 μs | 152.021 μs | 96.401 μs | 265.683 μs | 1.745 ms | 436.005 μs | 121.342 μs |
| to_spectral vector | Float32 128^3 | 14.196 ms | 10.079 ms | 6.842 ms | 6.110 ms | 14.984 ms | 10.519 ms | 5.321 ms | 3.854 ms | 1.355 ms | 3.183 ms | 473.980 μs | 198.352 μs |
| to_spectral vector | Float32 256^3 | 359.274 ms | 260.710 ms | 154.655 ms | 127.358 ms | 580.014 ms | 397.116 ms | 211.188 ms | 150.017 ms | — | 11.819 ms | 3.032 ms | 2.217 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | 6.247 s | 4.258 s | 2.215 s | 1.574 s | — | — | — | — |
| to_spectral vector | Float32 64^3 | 1.232 ms | 935.164 μs | 451.378 μs | 480.330 μs | 949.004 μs | 666.348 μs | 286.502 μs | 181.172 μs | 230.522 μs | 1.566 ms | 311.426 μs | 81.360 μs |
| to_spectral vector | Float64 128^3 | 34.978 ms | 30.297 ms | 19.984 ms | 18.093 ms | 41.663 ms | 29.762 ms | 19.943 ms | 14.923 ms | 4.144 ms | 6.538 ms | 1.592 ms | 1.179 ms |
| to_spectral vector | Float64 256^3 | 519.471 ms | 391.649 ms | 249.990 ms | 225.111 ms | 639.330 ms | 448.938 ms | 254.270 ms | 195.288 ms | — | 20.041 ms | 11.392 ms | 9.169 ms |
| to_spectral vector | Float64 512^3 | — | — | — | — | 5.122 s | 3.588 s | 2.022 s | 1.575 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.408 ms | 1.918 ms | 1.124 ms | 998.238 μs | 1.550 ms | 1.034 ms | 515.183 μs | 379.703 μs | 596.836 μs | 2.151 ms | 540.584 μs | 205.952 μs |

## algebra

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 432.952 μs | 3.604 ms | 1.846 ms | 949.549 μs | 162.161 μs | 2.936 ms | 1.467 ms | 736.828 μs | 351.303 μs | 1.943 ms | 397.824 μs | 81.631 μs |
| add! scalar | Float32 256^3 | 8.609 ms | 29.640 ms | 14.751 ms | 8.615 ms | 3.545 ms | 23.398 ms | 11.751 ms | 5.914 ms | — | 6.480 ms | 1.204 ms | 324.653 μs |
| add! scalar | Float32 512^3 | — | — | — | — | 40.586 ms | 187.263 ms | 93.785 ms | 48.325 ms | — | — | — | — |
| add! scalar | Float32 64^3 | 43.970 μs | 455.288 μs | 232.258 μs | 121.544 μs | 20.551 μs | 368.634 μs | 185.572 μs | 94.861 μs | 85.391 μs | 1.599 ms | 291.603 μs | 61.661 μs |
| add! scalar | Float64 128^3 | 1.546 ms | 3.635 ms | 1.861 ms | 1.118 ms | 325.041 μs | 2.939 ms | 1.471 ms | 740.318 μs | 354.693 μs | 2.024 ms | 379.045 μs | 83.630 μs |
| add! scalar | Float64 256^3 | 17.845 ms | 29.749 ms | 16.543 ms | 15.814 ms | 10.363 ms | 24.714 ms | 12.620 ms | 7.534 ms | — | 5.550 ms | 1.230 ms | 561.946 μs |
| add! scalar | Float64 512^3 | — | — | — | — | 83.944 ms | 187.614 ms | 94.248 ms | 73.617 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 85.313 μs | 462.446 μs | 235.816 μs | 122.582 μs | 40.361 μs | 368.384 μs | 185.351 μs | 95.091 μs | 83.741 μs | 1.494 ms | 370.453 μs | 55.571 μs |
| combine! vec | Float32 128^3 | 2.816 ms | 17.835 ms | 8.979 ms | 4.746 ms | 652.704 μs | 13.528 ms | 6.774 ms | 3.393 ms | — | — | 661.005 μs | 187.742 μs |
| combine! vec | Float32 256^3 | 26.999 ms | 144.556 ms | 72.271 ms | 37.146 ms | 13.984 ms | 108.471 ms | 54.945 ms | 27.330 ms | — | — | 3.456 ms | 1.012 ms |
| combine! vec | Float32 512^3 | — | — | — | — | 116.285 ms | 863.588 ms | 433.177 ms | 243.969 ms | — | — | — | — |
| combine! vec | Float32 64^3 | 129.781 μs | 2.217 ms | 1.120 ms | 574.521 μs | 61.790 μs | 1.684 ms | 843.286 μs | 426.284 μs | — | — | 335.255 μs | 71.381 μs |
| combine! vec | Float64 128^3 | 6.332 ms | 17.801 ms | 9.019 ms | 5.673 ms | 2.205 ms | 13.646 ms | 6.978 ms | 3.451 ms | — | — | 811.828 μs | 243.932 μs |
| combine! vec | Float64 256^3 | 53.973 ms | 145.694 ms | 73.271 ms | 47.019 ms | 28.681 ms | 107.737 ms | 54.021 ms | 27.437 ms | — | — | 4.040 ms | 1.577 ms |
| combine! vec | Float64 512^3 | — | — | — | — | 226.404 ms | 864.051 ms | 433.919 ms | 223.929 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 281.069 μs | 2.253 ms | 1.127 ms | 584.981 μs | 122.921 μs | 1.683 ms | 844.225 μs | 426.574 μs | — | — | 339.757 μs | 67.971 μs |
| cross! | Float32 128^3 | 4.928 ms | 16.678 ms | 8.579 ms | 4.349 ms | 3.038 ms | 12.724 ms | 6.403 ms | 3.214 ms | 1.223 ms | 3.445 ms | 741.028 μs | 188.962 μs |
| cross! | Float32 256^3 | 44.645 ms | 136.328 ms | 68.726 ms | 36.464 ms | 40.319 ms | 104.125 ms | 52.229 ms | 25.867 ms | — | 14.690 ms | 3.372 ms | 1.295 ms |
| cross! | Float32 512^3 | — | — | — | — | 252.147 ms | 815.980 ms | 408.478 ms | 230.448 ms | — | — | — | — |
| cross! | Float32 64^3 | 430.613 μs | 2.102 ms | 1.060 ms | 544.918 μs | 385.161 μs | 1.600 ms | 805.937 μs | 414.674 μs | 219.582 μs | 1.665 ms | 194.002 μs | 72.961 μs |
| cross! | Float64 128^3 | 10.318 ms | 16.153 ms | 9.063 ms | 8.561 ms | 5.152 ms | 12.860 ms | 6.677 ms | 3.275 ms | 1.263 ms | 2.603 ms | 799.815 μs | 366.163 μs |
| cross! | Float64 256^3 | 87.542 ms | 135.657 ms | 78.456 ms | 71.364 ms | 55.172 ms | 103.545 ms | 51.533 ms | 41.251 ms | — | 15.625 ms | 3.951 ms | 2.548 ms |
| cross! | Float64 512^3 | — | — | — | — | 376.180 ms | 819.850 ms | 410.270 ms | 342.653 ms | — | — | — | — |
| cross! | Float64 64^3 | 477.981 μs | 1.969 ms | 1.025 ms | 527.981 μs | 390.165 μs | 1.599 ms | 805.015 μs | 420.084 μs | 216.592 μs | 1.846 ms | 359.561 μs | 66.421 μs |
| det! tensor | Float32 128^3 | 10.987 ms | 13.761 ms | 7.122 ms | 3.557 ms | 9.176 ms | 11.142 ms | 5.594 ms | 2.822 ms | — | — | 611.298 μs | 183.692 μs |
| det! tensor | Float32 256^3 | 93.250 ms | 114.377 ms | 57.806 ms | 30.451 ms | 85.035 ms | 93.684 ms | 47.120 ms | 24.416 ms | — | — | 2.725 ms | 866.769 μs |
| det! tensor | Float32 512^3 | — | — | — | — | 625.856 ms | 732.316 ms | 365.973 ms | 204.927 ms | — | — | — | — |
| det! tensor | Float32 64^3 | 1.297 ms | 1.715 ms | 858.108 μs | 443.314 μs | 1.159 ms | 1.395 ms | 697.945 μs | 355.454 μs | — | — | 343.669 μs | 73.050 μs |
| det! tensor | Float64 128^3 | 11.869 ms | 14.164 ms | 7.146 ms | 5.213 ms | 9.983 ms | 11.261 ms | 5.839 ms | 2.963 ms | — | — | 863.681 μs | 256.033 μs |
| det! tensor | Float64 256^3 | 96.261 ms | 114.937 ms | 60.442 ms | 46.605 ms | 79.584 ms | 97.627 ms | 49.305 ms | 27.400 ms | — | — | 3.670 ms | 1.704 ms |
| det! tensor | Float64 512^3 | — | — | — | — | 844.724 ms | 902.801 ms | 417.773 ms | 234.508 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 1.370 ms | 1.700 ms | 876.781 μs | 448.779 μs | 1.188 ms | 1.399 ms | 702.935 μs | 355.353 μs | — | — | 363.869 μs | 74.411 μs |
| dot! vec.vec | Float32 128^3 | 2.845 ms | 6.781 ms | 3.477 ms | 1.797 ms | 2.486 ms | 5.208 ms | 2.642 ms | 1.321 ms | 538.855 μs | 2.430 ms | 428.856 μs | 115.811 μs |
| dot! vec.vec | Float32 256^3 | 24.880 ms | 54.576 ms | 28.409 ms | 16.191 ms | 29.986 ms | 45.003 ms | 22.431 ms | 11.531 ms | — | 9.651 ms | 1.580 ms | 650.026 μs |
| dot! vec.vec | Float32 512^3 | — | — | — | — | 196.381 ms | 343.518 ms | 169.864 ms | 93.841 ms | — | — | — | — |
| dot! vec.vec | Float32 64^3 | 335.576 μs | 853.337 μs | 424.365 μs | 222.250 μs | 309.071 μs | 658.317 μs | 329.742 μs | 166.401 μs | 112.901 μs | 1.663 ms | 303.591 μs | 61.140 μs |
| dot! vec.vec | Float64 128^3 | 4.571 ms | 6.749 ms | 3.730 ms | 3.376 ms | 3.389 ms | 5.241 ms | 2.829 ms | 1.332 ms | 618.906 μs | 2.505 ms | 533.841 μs | 194.362 μs |
| dot! vec.vec | Float64 256^3 | 42.263 ms | 56.172 ms | 33.798 ms | 31.532 ms | 34.901 ms | 46.512 ms | 21.712 ms | 18.605 ms | — | 9.784 ms | 2.043 ms | 1.236 ms |
| dot! vec.vec | Float64 512^3 | — | — | — | — | 227.157 ms | 346.343 ms | 167.721 ms | 152.733 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 342.211 μs | 852.801 μs | 428.310 μs | 220.958 μs | 318.094 μs | 653.708 μs | 330.212 μs | 168.001 μs | 127.611 μs | 1.656 ms | 162.125 μs | 59.141 μs |
| mul! tensor.vec | Float32 128^3 | 9.135 ms | 21.169 ms | 10.910 ms | 5.677 ms | 7.520 ms | 15.975 ms | 8.049 ms | 4.030 ms | 1.525 ms | 4.295 ms | 918.199 μs | 256.273 μs |
| mul! tensor.vec | Float32 256^3 | 79.033 ms | 171.834 ms | 87.930 ms | 50.881 ms | 70.379 ms | 134.110 ms | 68.472 ms | 35.368 ms | — | 16.892 ms | 4.152 ms | 1.773 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | 566.796 ms | 1.057 s | 514.361 ms | 318.466 ms | — | — | — | — |
| mul! tensor.vec | Float32 64^3 | 1.011 ms | 2.628 ms | 1.330 ms | 686.859 μs | 915.574 μs | 2.001 ms | 1.009 ms | 521.365 μs | 255.702 μs | 1.882 ms | 320.574 μs | 73.571 μs |
| mul! tensor.vec | Float64 128^3 | 15.002 ms | 21.129 ms | 12.108 ms | 11.257 ms | 11.025 ms | 16.382 ms | 8.282 ms | 4.185 ms | 1.748 ms | 4.757 ms | 982.624 μs | 486.094 μs |
| mul! tensor.vec | Float64 256^3 | 124.860 ms | 175.649 ms | 102.925 ms | 95.531 ms | 92.746 ms | 142.827 ms | 65.645 ms | 54.515 ms | — | 17.818 ms | 5.402 ms | 3.522 ms |
| mul! tensor.vec | Float64 512^3 | — | — | — | — | 624.066 ms | 1.041 s | 516.553 ms | 456.871 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 1.182 ms | 2.558 ms | 1.329 ms | 699.429 μs | 927.720 μs | 2.010 ms | 1.019 ms | 513.775 μs | 280.183 μs | 1.951 ms | 449.785 μs | 76.701 μs |
| norm! vec | Float32 128^3 | 769.840 μs | 4.963 ms | 2.529 ms | 1.296 ms | 217.231 μs | 3.756 ms | 1.877 ms | 950.201 μs | 411.304 μs | 2.110 ms | 398.094 μs | 88.811 μs |
| norm! vec | Float32 256^3 | 10.942 ms | 39.879 ms | 20.810 ms | 10.577 ms | 5.331 ms | 30.367 ms | 15.275 ms | 7.668 ms | — | 7.304 ms | 1.216 ms | 399.324 μs |
| norm! vec | Float32 512^3 | — | — | — | — | 53.028 ms | 240.952 ms | 121.645 ms | 64.634 ms | — | — | — | — |
| norm! vec | Float32 64^3 | 56.961 μs | 621.762 μs | 313.206 μs | 161.352 μs | 31.510 μs | 472.315 μs | 236.772 μs | 120.332 μs | 100.251 μs | 1.526 ms | 293.826 μs | 62.281 μs |
| norm! vec | Float64 128^3 | 2.262 ms | 5.010 ms | 2.563 ms | 1.782 ms | 484.072 μs | 3.941 ms | 1.981 ms | 996.621 μs | 463.344 μs | 1.434 ms | 594.819 μs | 147.531 μs |
| norm! vec | Float64 256^3 | 22.598 ms | 41.441 ms | 22.175 ms | 19.803 ms | 11.891 ms | 31.976 ms | 16.019 ms | 10.209 ms | — | 9.850 ms | 2.466 ms | 725.558 μs |
| norm! vec | Float64 512^3 | — | — | — | — | 97.990 ms | 253.059 ms | 126.780 ms | 92.726 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 160.955 μs | 628.865 μs | 321.851 μs | 167.630 μs | 56.191 μs | 493.386 μs | 248.512 μs | 125.971 μs | 101.231 μs | 1.681 ms | 330.640 μs | 68.531 μs |
| tr! tensor | Float32 128^3 | 770.255 μs | 4.438 ms | 2.249 ms | 1.167 ms | 214.311 μs | 3.441 ms | 1.723 ms | 866.910 μs | — | — | 381.081 μs | 87.741 μs |
| tr! tensor | Float32 256^3 | 10.961 ms | 36.969 ms | 18.241 ms | 10.382 ms | 5.174 ms | 27.482 ms | 13.783 ms | 6.948 ms | — | — | 1.214 ms | 390.044 μs |
| tr! tensor | Float32 512^3 | — | — | — | — | 48.196 ms | 248.660 ms | 129.896 ms | 70.534 ms | — | — | — | — |
| tr! tensor | Float32 64^3 | 53.848 μs | 559.549 μs | 281.380 μs | 145.533 μs | 27.380 μs | 431.495 μs | 216.702 μs | 110.961 μs | — | — | 301.965 μs | 69.871 μs |
| tr! tensor | Float64 128^3 | 2.239 ms | 4.366 ms | 2.258 ms | 1.758 ms | 459.023 μs | 3.453 ms | 1.735 ms | 873.869 μs | — | — | 441.365 μs | 123.231 μs |
| tr! tensor | Float64 256^3 | 22.145 ms | 36.362 ms | 20.738 ms | 19.678 ms | 11.684 ms | 27.560 ms | 13.816 ms | 10.075 ms | — | — | 1.340 ms | 719.957 μs |
| tr! tensor | Float64 512^3 | — | — | — | — | 95.468 ms | 386.229 ms | 162.030 ms | 107.905 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 107.309 μs | 550.708 μs | 276.150 μs | 145.507 μs | 53.191 μs | 431.015 μs | 218.531 μs | 111.241 μs | — | — | 315.126 μs | 58.991 μs |

## operators

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.332 ms | 9.191 ms | 4.550 ms | 2.400 ms | 3.740 ms | 6.522 ms | 3.275 ms | 1.672 ms | 697.807 μs | 2.544 ms | 551.324 μs | 122.031 μs |
| curl! vec->vec | Float32 256^3 | 43.101 ms | 72.367 ms | 36.899 ms | 25.627 ms | 30.284 ms | 51.761 ms | 25.973 ms | 13.276 ms | — | 10.865 ms | 1.982 ms | 829.799 μs |
| curl! vec->vec | Float32 512^3 | — | — | — | — | 242.732 ms | 412.359 ms | 206.971 ms | 130.199 ms | — | — | — | — |
| curl! vec->vec | Float32 64^3 | 644.070 μs | 1.158 ms | 585.317 μs | 310.884 μs | 489.602 μs | 835.400 μs | 423.503 μs | 223.832 μs | 182.902 μs | 1.646 ms | 174.757 μs | 70.241 μs |
| curl! vec->vec | Float64 128^3 | 6.542 ms | 9.174 ms | 5.281 ms | 4.185 ms | 3.539 ms | 6.798 ms | 3.405 ms | 1.729 ms | 824.588 μs | 3.153 ms | 750.075 μs | 247.462 μs |
| curl! vec->vec | Float64 256^3 | 58.089 ms | 73.095 ms | 49.179 ms | 40.722 ms | 36.434 ms | 53.974 ms | 27.256 ms | 25.663 ms | — | 13.647 ms | 3.489 ms | 1.594 ms |
| curl! vec->vec | Float64 512^3 | — | — | — | — | 280.133 ms | 429.935 ms | 223.408 ms | 222.094 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 524.406 μs | 1.127 ms | 582.203 μs | 304.882 μs | 446.005 μs | 876.140 μs | 465.453 μs | 241.202 μs | 186.242 μs | 1.786 ms | 393.548 μs | 78.011 μs |
| divergence! vec->scalar | Float32 128^3 | 3.662 ms | 3.649 ms | 1.890 ms | 993.554 μs | 3.350 ms | 2.738 ms | 1.378 ms | 692.088 μs | 326.353 μs | 1.957 ms | 400.152 μs | 85.391 μs |
| divergence! vec->scalar | Float32 256^3 | 28.920 ms | 29.850 ms | 15.081 ms | 9.627 ms | 26.756 ms | 21.693 ms | 10.918 ms | 5.515 ms | — | 5.523 ms | 1.230 ms | 404.274 μs |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | 213.001 ms | 173.570 ms | 86.950 ms | 49.911 ms | — | — | — | — |
| divergence! vec->scalar | Float32 64^3 | 427.458 μs | 465.493 μs | 239.116 μs | 125.776 μs | 436.542 μs | 356.804 μs | 179.621 μs | 93.931 μs | 93.900 μs | 1.537 ms | 325.554 μs | 57.810 μs |
| divergence! vec->scalar | Float64 128^3 | 3.676 ms | 3.697 ms | 2.077 ms | 1.800 ms | 3.352 ms | 2.796 ms | 1.402 ms | 714.688 μs | 407.644 μs | 2.306 ms | 448.700 μs | 132.451 μs |
| divergence! vec->scalar | Float64 256^3 | 32.844 ms | 31.194 ms | 21.140 ms | 19.566 ms | 27.365 ms | 22.169 ms | 11.183 ms | 10.240 ms | — | 7.090 ms | 1.844 ms | 728.987 μs |
| divergence! vec->scalar | Float64 512^3 | — | — | — | — | 212.581 ms | 177.794 ms | 93.218 ms | 93.025 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 415.329 μs | 468.003 μs | 235.837 μs | 123.143 μs | 443.964 μs | 370.065 μs | 186.331 μs | 97.181 μs | 103.111 μs | 344.869 μs | 324.934 μs | 65.870 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.623 ms | 4.665 ms | 2.354 ms | 1.231 ms | 3.722 ms | 3.249 ms | 1.644 ms | 822.499 μs | — | — | 546.243 μs | 85.550 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 35.646 ms | 37.462 ms | 19.009 ms | 11.723 ms | 29.558 ms | 25.654 ms | 12.933 ms | 6.507 ms | — | — | 1.092 ms | 484.295 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | — | — | — | — | 235.158 ms | 204.877 ms | 102.952 ms | 60.465 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 550.278 μs | 583.344 μs | 297.431 μs | 156.406 μs | 480.472 μs | 423.805 μs | 212.921 μs | 111.061 μs | — | — | 283.459 μs | 63.161 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.807 ms | 4.621 ms | 2.647 ms | 2.353 ms | 3.573 ms | 3.465 ms | 1.735 ms | 872.990 μs | — | — | 608.926 μs | 184.481 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 40.931 ms | 38.067 ms | 25.245 ms | 23.779 ms | 29.555 ms | 27.453 ms | 13.877 ms | 12.819 ms | — | — | 2.117 ms | 892.369 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | — | — | — | — | 235.779 ms | 222.121 ms | 114.289 ms | 112.635 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 552.953 μs | 582.643 μs | 301.498 μs | 156.491 μs | 476.325 μs | 459.645 μs | 229.792 μs | 119.081 μs | — | — | 153.083 μs | 73.261 μs |
| gradient! scalar->vec | Float32 128^3 | 3.878 ms | 6.343 ms | 3.184 ms | 1.645 ms | 1.934 ms | 4.525 ms | 2.273 ms | 1.149 ms | 560.525 μs | 2.377 ms | 437.501 μs | 105.111 μs |
| gradient! scalar->vec | Float32 256^3 | 32.209 ms | 49.818 ms | 25.284 ms | 18.636 ms | 15.414 ms | 35.871 ms | 18.030 ms | 9.120 ms | — | 7.929 ms | 1.627 ms | 594.196 μs |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | 127.867 ms | 286.353 ms | 143.499 ms | 91.759 ms | — | — | — | — |
| gradient! scalar->vec | Float32 64^3 | 482.604 μs | 792.999 μs | 408.421 μs | 217.904 μs | 248.631 μs | 580.137 μs | 294.142 μs | 153.162 μs | 133.261 μs | 1.681 ms | 361.502 μs | 65.911 μs |
| gradient! scalar->vec | Float64 128^3 | 4.097 ms | 6.177 ms | 3.420 ms | 2.271 ms | 1.893 ms | 4.574 ms | 2.308 ms | 1.166 ms | 605.225 μs | 2.717 ms | 678.031 μs | 142.581 μs |
| gradient! scalar->vec | Float64 256^3 | 41.972 ms | 50.278 ms | 33.673 ms | 27.350 ms | 21.187 ms | 36.375 ms | 18.327 ms | 16.658 ms | — | 10.338 ms | 2.694 ms | 1.109 ms |
| gradient! scalar->vec | Float64 512^3 | — | — | — | — | 177.093 ms | 290.721 ms | 163.100 ms | 164.094 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 372.986 μs | 803.740 μs | 402.820 μs | 216.375 μs | 242.973 μs | 588.927 μs | 296.812 μs | 155.932 μs | 153.172 μs | 1.872 ms | 375.405 μs | 67.101 μs |
| helmholtz! vec->vec | Float32 128^3 | 5.347 ms | 2.685 ms | 1.515 ms | 1.301 ms | 4.529 ms | 2.272 ms | 1.160 ms | 589.656 μs | 1.480 ms | 4.174 ms | 208.114 μs | 90.721 μs |
| helmholtz! vec->vec | Float32 256^3 | 43.018 ms | 22.153 ms | 18.285 ms | 17.934 ms | 35.385 ms | 18.284 ms | 9.376 ms | 8.621 ms | — | 16.637 ms | 1.071 ms | 617.496 μs |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | 281.449 ms | 147.313 ms | 83.857 ms | 85.344 ms | — | — | — | — |
| helmholtz! vec->vec | Float32 64^3 | 709.122 μs | 357.658 μs | 187.864 μs | 99.692 μs | 609.453 μs | 311.974 μs | 157.331 μs | 84.821 μs | 286.333 μs | 1.935 ms | 321.721 μs | 65.161 μs |
| helmholtz! vec->vec | Float64 128^3 | 6.186 ms | 4.285 ms | 3.888 ms | 3.745 ms | 5.222 ms | 2.643 ms | 1.315 ms | 672.917 μs | 1.802 ms | 5.921 ms | 681.569 μs | 234.392 μs |
| helmholtz! vec->vec | Float64 256^3 | 52.605 ms | 39.695 ms | 36.920 ms | 35.988 ms | 42.525 ms | 23.688 ms | 19.501 ms | 19.647 ms | — | 18.240 ms | 2.817 ms | 1.319 ms |
| helmholtz! vec->vec | Float64 512^3 | — | — | — | — | 366.976 ms | 190.254 ms | 165.603 ms | 166.792 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 785.322 μs | 395.868 μs | 200.525 μs | 109.877 μs | 703.318 μs | 358.564 μs | 187.661 μs | 101.011 μs | 342.613 μs | 2.260 ms | 381.048 μs | 82.701 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 6.384 ms | 3.279 ms | 1.877 ms | 1.682 ms | 5.122 ms | 2.577 ms | 1.289 ms | 667.697 μs | — | — | 206.405 μs | 130.841 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 51.203 ms | 26.002 ms | 20.246 ms | 19.805 ms | 41.554 ms | 21.358 ms | 11.123 ms | 10.009 ms | — | — | 969.713 μs | 681.816 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | — | — | — | — | 325.328 ms | 171.734 ms | 94.569 ms | 95.371 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 840.993 μs | 434.448 μs | 222.258 μs | 115.997 μs | 689.463 μs | 345.534 μs | 174.471 μs | 93.541 μs | — | — | 346.382 μs | 73.191 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 7.169 ms | 4.962 ms | 4.484 ms | 4.381 ms | 5.988 ms | 3.030 ms | 1.490 ms | 805.589 μs | — | — | 814.421 μs | 279.893 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 60.187 ms | 43.988 ms | 40.900 ms | 39.777 ms | 48.383 ms | 28.040 ms | 22.203 ms | 22.317 ms | — | — | 3.617 ms | 1.685 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | — | — | — | — | 420.680 ms | 225.582 ms | 185.453 ms | 186.387 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 933.104 μs | 462.957 μs | 236.175 μs | 124.703 μs | 765.778 μs | 387.754 μs | 201.281 μs | 108.291 μs | — | — | 374.563 μs | 91.621 μs |
| laplacian! scalar | Float32 128^3 | 2.061 ms | 2.746 ms | 1.352 ms | 721.537 μs | 2.147 ms | 2.127 ms | 1.067 ms | 535.835 μs | 265.103 μs | 1.910 ms | 357.451 μs | 72.001 μs |
| laplacian! scalar | Float32 256^3 | 16.755 ms | 22.106 ms | 11.152 ms | 6.085 ms | 17.067 ms | 16.903 ms | 8.477 ms | 4.257 ms | — | 5.490 ms | 946.817 μs | 259.853 μs |
| laplacian! scalar | Float32 512^3 | — | — | — | — | 135.937 ms | 134.829 ms | 67.650 ms | 35.182 ms | — | — | — | — |
| laplacian! scalar | Float32 64^3 | 252.574 μs | 346.110 μs | 176.807 μs | 93.179 μs | 274.891 μs | 269.923 μs | 135.811 μs | 69.841 μs | 83.431 μs | 1.563 ms | 125.781 μs | 56.320 μs |
| laplacian! scalar | Float64 128^3 | 2.114 ms | 2.769 ms | 1.409 ms | 730.468 μs | 2.203 ms | 2.239 ms | 1.121 ms | 565.726 μs | 278.082 μs | 1.957 ms | 361.040 μs | 71.170 μs |
| laplacian! scalar | Float64 256^3 | 17.876 ms | 22.542 ms | 13.154 ms | 10.094 ms | 17.746 ms | 17.801 ms | 8.933 ms | 4.884 ms | — | 4.740 ms | 1.007 ms | 402.514 μs |
| laplacian! scalar | Float64 512^3 | — | — | — | — | 141.011 ms | 142.053 ms | 71.269 ms | 54.691 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 257.704 μs | 346.854 μs | 181.490 μs | 95.390 μs | 281.113 μs | 284.074 μs | 142.601 μs | 73.641 μs | 84.420 μs | 1.586 ms | 311.696 μs | 58.721 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 13.277 ms | 24.177 ms | 12.287 ms | 6.586 ms | 8.916 ms | 17.486 ms | 8.815 ms | 4.480 ms | — | — | 918.561 μs | 256.043 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 105.902 ms | 188.498 ms | 97.058 ms | 71.424 ms | 72.112 ms | 138.861 ms | 69.625 ms | 35.967 ms | — | — | 4.854 ms | 2.116 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | — | — | — | — | 602.316 ms | 1.107 s | 556.499 ms | 395.257 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.561 ms | 3.069 ms | 1.563 ms | 833.393 μs | 1.156 ms | 2.257 ms | 1.142 ms | 606.616 μs | — | — | 467.259 μs | 103.081 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 18.609 ms | 24.173 ms | 15.134 ms | 11.540 ms | 8.427 ms | 18.086 ms | 9.079 ms | 4.869 ms | — | — | 1.452 ms | 566.696 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 155.770 ms | 192.065 ms | 140.340 ms | 107.575 ms | 90.333 ms | 144.371 ms | 74.247 ms | 71.291 ms | — | — | 8.458 ms | 4.187 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | — | — | — | — | 684.425 ms | 1.148 s | 609.905 ms | 609.337 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.201 ms | 3.003 ms | 1.552 ms | 822.419 μs | 1.023 ms | 2.336 ms | 1.188 ms | 626.326 μs | — | — | 503.754 μs | 124.821 μs |

## convolution

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.849 ms | 2.252 ms | 1.117 ms | 583.670 μs | 1.364 ms | 1.738 ms | 872.978 μs | 440.335 μs | 296.642 μs | 1.855 ms | 274.024 μs | 129.851 μs |
| assignment_window | Float32 256^3 | 28.203 ms | 24.888 ms | 9.162 ms | 4.771 ms | 18.186 ms | 18.175 ms | 9.142 ms | 4.756 ms | — | 3.952 ms | 906.052 μs | 262.913 μs |
| assignment_window | Float32 512^3 | — | — | — | — | 150.728 ms | 147.085 ms | 72.745 ms | 39.209 ms | — | — | — | — |
| assignment_window | Float32 64^3 | 230.412 μs | 284.137 μs | 145.571 μs | 79.361 μs | 176.081 μs | 223.803 μs | 112.851 μs | 59.171 μs | 138.651 μs | 1.640 ms | 408.218 μs | 118.541 μs |
| assignment_window | Float64 128^3 | 1.923 ms | 2.206 ms | 1.137 ms | 684.038 μs | 1.546 ms | 1.778 ms | 891.088 μs | 451.265 μs | 306.863 μs | 1.901 ms | 456.909 μs | 139.211 μs |
| assignment_window | Float64 256^3 | 42.182 ms | 32.063 ms | 16.713 ms | 9.242 ms | 27.671 ms | 22.629 ms | 11.401 ms | 6.778 ms | — | 4.237 ms | 975.561 μs | 286.443 μs |
| assignment_window | Float64 512^3 | — | — | — | — | 221.053 ms | 179.986 ms | 91.336 ms | 60.916 ms | — | — | — | — |
| assignment_window | Float64 64^3 | 244.355 μs | 282.564 μs | 146.029 μs | 83.786 μs | 198.572 μs | 228.883 μs | 116.531 μs | 60.790 μs | 141.232 μs | 1.542 ms | 221.844 μs | 132.221 μs |
| combine!∘kernel vector | Float32 128^3 | 8.757 ms | 11.414 ms | 5.701 ms | 2.921 ms | 8.058 ms | 8.230 ms | 4.105 ms | 2.063 ms | — | — | 514.875 μs | 176.962 μs |
| combine!∘kernel vector | Float32 256^3 | 70.758 ms | 90.386 ms | 45.671 ms | 24.701 ms | 63.815 ms | 65.010 ms | 32.614 ms | 16.438 ms | — | — | 2.214 ms | 1.062 ms |
| combine!∘kernel vector | Float32 512^3 | — | — | — | — | 508.046 ms | 529.973 ms | 264.743 ms | 145.971 ms | — | — | — | — |
| combine!∘kernel vector | Float32 64^3 | 1.189 ms | 1.416 ms | 720.281 μs | 369.248 μs | 1.022 ms | 1.042 ms | 558.604 μs | 266.143 μs | — | — | 325.364 μs | 58.520 μs |
| combine!∘kernel vector | Float64 128^3 | 10.046 ms | 11.079 ms | 5.966 ms | 5.261 ms | 7.444 ms | 8.784 ms | 4.411 ms | 2.221 ms | — | — | 766.781 μs | 309.663 μs |
| combine!∘kernel vector | Float64 256^3 | 82.613 ms | 91.120 ms | 51.979 ms | 46.381 ms | 59.205 ms | 70.310 ms | 35.396 ms | 24.207 ms | — | — | 3.711 ms | 2.090 ms |
| combine!∘kernel vector | Float64 512^3 | — | — | — | — | 493.418 ms | 569.424 ms | 285.871 ms | 226.329 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 1.196 ms | 1.410 ms | 719.913 μs | 365.096 μs | 967.011 μs | 1.117 ms | 560.844 μs | 284.093 μs | — | — | 353.470 μs | 71.131 μs |
| convolve! scalar | Float32 128^3 | 1.642 ms | 2.071 ms | 1.064 ms | 545.465 μs | 916.647 μs | 1.496 ms | 751.247 μs | 379.134 μs | 220.032 μs | 1.755 ms | 158.468 μs | 66.141 μs |
| convolve! scalar | Float32 256^3 | 13.765 ms | 17.286 ms | 8.580 ms | 7.769 ms | 7.594 ms | 11.882 ms | 5.950 ms | 2.996 ms | — | 3.659 ms | 720.153 μs | 312.984 μs |
| convolve! scalar | Float32 512^3 | — | — | — | — | 62.340 ms | 94.628 ms | 47.550 ms | 37.388 ms | — | — | — | — |
| convolve! scalar | Float32 64^3 | 201.161 μs | 268.019 μs | 135.606 μs | 72.302 μs | 117.180 μs | 192.012 μs | 97.230 μs | 50.980 μs | 78.951 μs | 1.480 ms | 303.195 μs | 51.491 μs |
| convolve! scalar | Float64 128^3 | 1.960 ms | 2.117 ms | 1.319 ms | 996.734 μs | 1.006 ms | 1.665 ms | 832.278 μs | 420.645 μs | 302.553 μs | 1.784 ms | 211.581 μs | 81.801 μs |
| convolve! scalar | Float64 256^3 | 19.251 ms | 18.151 ms | 13.824 ms | 12.228 ms | 11.056 ms | 13.257 ms | 7.611 ms | 7.574 ms | — | 4.442 ms | 1.058 ms | 559.065 μs |
| convolve! scalar | Float64 512^3 | — | — | — | — | 92.269 ms | 106.084 ms | 73.446 ms | 74.522 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 179.774 μs | 260.094 μs | 133.456 μs | 71.629 μs | 127.771 μs | 211.743 μs | 107.311 μs | 55.381 μs | 78.591 μs | 1.618 ms | 337.239 μs | 72.791 μs |
| convolve! vector | Float32 128^3 | 6.067 ms | 9.107 ms | 4.604 ms | 2.378 ms | 4.556 ms | 6.757 ms | 3.399 ms | 1.703 ms | 731.727 μs | 2.557 ms | 472.728 μs | 120.741 μs |
| convolve! vector | Float32 256^3 | 49.271 ms | 71.294 ms | 36.739 ms | 23.820 ms | 35.944 ms | 53.703 ms | 26.976 ms | 13.539 ms | — | 10.821 ms | 1.843 ms | 822.928 μs |
| convolve! vector | Float32 512^3 | — | — | — | — | 285.744 ms | 428.427 ms | 215.006 ms | 124.030 ms | — | — | — | — |
| convolve! vector | Float32 64^3 | 736.726 μs | 1.139 ms | 583.108 μs | 299.989 μs | 581.493 μs | 861.130 μs | 432.323 μs | 218.712 μs | 161.751 μs | 1.595 ms | 314.803 μs | 63.540 μs |
| convolve! vector | Float64 128^3 | 7.164 ms | 9.344 ms | 5.209 ms | 4.338 ms | 4.774 ms | 6.945 ms | 3.485 ms | 1.750 ms | 792.657 μs | 2.910 ms | 640.119 μs | 239.373 μs |
| convolve! vector | Float64 256^3 | 61.696 ms | 76.413 ms | 47.698 ms | 40.195 ms | 42.969 ms | 55.179 ms | 27.696 ms | 24.209 ms | — | 12.297 ms | 2.764 ms | 1.604 ms |
| convolve! vector | Float64 512^3 | — | — | — | — | 333.045 ms | 440.842 ms | 226.522 ms | 225.344 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 704.772 μs | 1.148 ms | 588.441 μs | 303.859 μs | 600.957 μs | 884.090 μs | 442.993 μs | 225.133 μs | 167.451 μs | 1.655 ms | 357.520 μs | 64.311 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.724 ms | 3.924 ms | 2.466 ms | 1.347 ms | 3.817 ms | 2.551 ms | 1.372 ms | 711.348 μs | — | — | 386.470 μs | 80.361 μs |
| exponential_convolve! scalar | Float32 256^3 | 34.753 ms | 24.909 ms | 13.162 ms | 7.389 ms | 28.523 ms | 18.729 ms | 9.447 ms | 4.857 ms | — | — | 846.822 μs | 243.962 μs |
| exponential_convolve! scalar | Float32 512^3 | — | — | — | — | 224.697 ms | 147.883 ms | 75.024 ms | 38.386 ms | — | — | — | — |
| exponential_convolve! scalar | Float32 64^3 | 2.197 ms | 1.310 ms | 698.000 μs | 362.265 μs | 691.623 μs | 512.386 μs | 273.772 μs | 141.481 μs | — | — | 355.701 μs | 57.640 μs |
| exponential_convolve! scalar | Float64 128^3 | 8.246 ms | 5.664 ms | 3.308 ms | 1.972 ms | 5.846 ms | 4.210 ms | 2.156 ms | 1.099 ms | — | — | 452.793 μs | 130.352 μs |
| exponential_convolve! scalar | Float64 256^3 | 56.283 ms | 40.122 ms | 21.475 ms | 12.566 ms | 40.564 ms | 30.555 ms | 15.543 ms | 7.870 ms | — | — | 1.684 ms | 695.737 μs |
| exponential_convolve! scalar | Float64 512^3 | — | — | — | — | 314.339 ms | 235.924 ms | 117.740 ms | 62.136 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 737.673 μs | 563.050 μs | 285.564 μs | 150.037 μs | 694.597 μs | 514.236 μs | 257.702 μs | 132.421 μs | — | — | 332.052 μs | 68.881 μs |
| exponential_convolve! vector | Float32 128^3 | 19.113 ms | 15.232 ms | 8.154 ms | 4.885 ms | 13.387 ms | 10.065 ms | 5.168 ms | 2.727 ms | — | — | 669.992 μs | 137.001 μs |
| exponential_convolve! vector | Float32 256^3 | 118.377 ms | 97.947 ms | 50.681 ms | 26.940 ms | 101.136 ms | 75.674 ms | 38.012 ms | 19.324 ms | — | — | 2.256 ms | 699.927 μs |
| exponential_convolve! vector | Float32 512^3 | — | — | — | — | 798.917 ms | 607.391 ms | 304.673 ms | 164.445 ms | — | — | — | — |
| exponential_convolve! vector | Float32 64^3 | 6.918 ms | 4.417 ms | 2.307 ms | 1.218 ms | 2.274 ms | 1.879 ms | 963.808 μs | 506.756 μs | — | — | 336.138 μs | 69.481 μs |
| exponential_convolve! vector | Float64 128^3 | 27.195 ms | 20.847 ms | 11.051 ms | 6.487 ms | 19.116 ms | 14.663 ms | 7.365 ms | 3.771 ms | — | — | 928.874 μs | 287.113 μs |
| exponential_convolve! vector | Float64 256^3 | 186.872 ms | 146.013 ms | 76.188 ms | 40.859 ms | 139.889 ms | 106.989 ms | 53.805 ms | 27.570 ms | — | — | 4.924 ms | 1.951 ms |
| exponential_convolve! vector | Float64 512^3 | — | — | — | — | 1.083 s | 833.510 ms | 418.301 ms | 219.035 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.535 ms | 2.166 ms | 1.110 ms | 568.887 μs | 2.329 ms | 1.794 ms | 889.946 μs | 448.624 μs | — | — | 429.764 μs | 84.631 μs |
| spectral_band | Float32 128^3 | 4.200 ms | 3.422 ms | 1.715 ms | 886.555 μs | 3.865 ms | 2.640 ms | 1.324 ms | 664.767 μs | 334.154 μs | 2.050 ms | 400.569 μs | 88.951 μs |
| spectral_band | Float32 256^3 | 46.789 ms | 33.835 ms | 13.683 ms | 7.165 ms | 38.965 ms | 25.136 ms | 12.614 ms | 6.430 ms | — | 6.344 ms | 986.036 μs | 270.963 μs |
| spectral_band | Float32 512^3 | — | — | — | — | 315.682 ms | 201.210 ms | 100.455 ms | 55.525 ms | — | — | — | — |
| spectral_band | Float32 64^3 | 523.213 μs | 427.685 μs | 219.260 μs | 116.255 μs | 492.562 μs | 334.994 μs | 169.192 μs | 86.461 μs | 106.071 μs | 1.537 ms | 142.500 μs | 73.500 μs |
| spectral_band | Float64 128^3 | 4.273 ms | 3.403 ms | 1.740 ms | 942.494 μs | 3.971 ms | 2.643 ms | 1.347 ms | 676.407 μs | 361.113 μs | 2.105 ms | 432.997 μs | 95.501 μs |
| spectral_band | Float64 256^3 | 60.189 ms | 41.285 ms | 21.167 ms | 11.444 ms | 48.395 ms | 30.220 ms | 16.310 ms | 8.053 ms | — | 5.611 ms | 1.281 ms | 285.083 μs |
| spectral_band | Float64 512^3 | — | — | — | — | 393.723 ms | 259.771 ms | 126.072 ms | 64.506 ms | — | — | — | — |
| spectral_band | Float64 64^3 | 523.418 μs | 433.651 μs | 221.418 μs | 123.355 μs | 505.155 μs | 342.434 μs | 171.811 μs | 87.941 μs | 110.411 μs | 1.651 ms | 347.331 μs | 79.851 μs |
| spectral_cutoff | Float32 128^3 | 4.207 ms | 3.352 ms | 1.718 ms | 878.672 μs | 3.867 ms | 2.596 ms | 1.322 ms | 663.777 μs | 331.623 μs | 2.046 ms | 404.955 μs | 89.561 μs |
| spectral_cutoff | Float32 256^3 | 46.822 ms | 34.547 ms | 13.809 ms | 7.206 ms | 39.113 ms | 25.162 ms | 12.647 ms | 6.407 ms | — | 5.403 ms | 1.068 ms | 267.103 μs |
| spectral_cutoff | Float32 512^3 | — | — | — | — | 311.793 ms | 200.281 ms | 104.596 ms | 59.387 ms | — | — | — | — |
| spectral_cutoff | Float32 64^3 | 509.374 μs | 427.396 μs | 220.422 μs | 116.163 μs | 492.342 μs | 333.713 μs | 169.522 μs | 86.381 μs | 108.881 μs | 1.625 ms | 322.911 μs | 71.001 μs |
| spectral_cutoff | Float64 128^3 | 4.197 ms | 3.462 ms | 1.738 ms | 974.235 μs | 3.971 ms | 2.691 ms | 1.348 ms | 675.867 μs | 351.793 μs | 2.120 ms | 405.973 μs | 90.111 μs |
| spectral_cutoff | Float64 256^3 | 59.604 ms | 41.886 ms | 21.099 ms | 11.370 ms | 48.204 ms | 30.802 ms | 15.885 ms | 8.056 ms | — | 5.621 ms | 1.287 ms | 282.033 μs |
| spectral_cutoff | Float64 512^3 | — | — | — | — | 395.375 ms | 236.548 ms | 125.185 ms | 66.199 ms | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 534.454 μs | 433.480 μs | 222.257 μs | 118.498 μs | 504.916 μs | 342.944 μs | 171.662 μs | 87.851 μs | 117.711 μs | 1.647 ms | 355.066 μs | 80.170 μs |
| squared_wavenumber_field | Float32 128^3 | 1.841 ms | 2.230 ms | 1.130 ms | 579.126 μs | 1.374 ms | 1.734 ms | 871.078 μs | 438.155 μs | 262.463 μs | 1.824 ms | 354.675 μs | 85.261 μs |
| squared_wavenumber_field | Float32 256^3 | 27.936 ms | 25.131 ms | 9.074 ms | 4.704 ms | 18.540 ms | 18.316 ms | 9.163 ms | 4.722 ms | — | 3.812 ms | 819.707 μs | 216.823 μs |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | 152.447 ms | 144.092 ms | 73.404 ms | 38.568 ms | — | — | — | — |
| squared_wavenumber_field | Float32 64^3 | 228.975 μs | 279.362 μs | 144.217 μs | 77.567 μs | 176.591 μs | 222.022 μs | 112.311 μs | 58.101 μs | 91.321 μs | 1.517 ms | 373.013 μs | 67.290 μs |
| squared_wavenumber_field | Float64 128^3 | 1.940 ms | 2.180 ms | 1.119 ms | 706.287 μs | 1.419 ms | 1.767 ms | 886.748 μs | 447.025 μs | 264.163 μs | 1.805 ms | 396.751 μs | 83.761 μs |
| squared_wavenumber_field | Float64 256^3 | 41.271 ms | 31.606 ms | 16.422 ms | 9.209 ms | 28.318 ms | 22.771 ms | 11.434 ms | 6.764 ms | — | 4.151 ms | 835.978 μs | 239.402 μs |
| squared_wavenumber_field | Float64 512^3 | — | — | — | — | 218.457 ms | 177.798 ms | 91.077 ms | 53.986 ms | — | — | — | — |
| squared_wavenumber_field | Float64 64^3 | 245.685 μs | 283.214 μs | 143.709 μs | 81.335 μs | 182.182 μs | 226.743 μs | 114.650 μs | 59.411 μs | 88.931 μs | 1.612 ms | 323.221 μs | 77.781 μs |
| translation_kernel | Float32 128^3 | 1.841 ms | 2.625 ms | 1.356 ms | 680.137 μs | 1.536 ms | 1.773 ms | 898.788 μs | 455.875 μs | — | — | 394.496 μs | 125.561 μs |
| translation_kernel | Float32 256^3 | 28.357 ms | 27.746 ms | 10.625 ms | 5.481 ms | 19.905 ms | 18.763 ms | 9.473 ms | 4.833 ms | — | — | 856.930 μs | 262.582 μs |
| translation_kernel | Float32 512^3 | — | — | — | — | 166.014 ms | 150.326 ms | 75.674 ms | 42.163 ms | — | — | — | — |
| translation_kernel | Float32 64^3 | 232.572 μs | 329.267 μs | 170.177 μs | 91.174 μs | 197.350 μs | 229.633 μs | 116.561 μs | 61.351 μs | — | — | 342.271 μs | 98.481 μs |
| translation_kernel | Float64 128^3 | 1.833 ms | 2.683 ms | 1.382 ms | 740.848 μs | 1.452 ms | 1.904 ms | 972.708 μs | 490.736 μs | — | — | 453.284 μs | 140.771 μs |
| translation_kernel | Float64 256^3 | 41.397 ms | 34.957 ms | 18.599 ms | 9.924 ms | 27.030 ms | 24.493 ms | 12.476 ms | 6.972 ms | — | — | 1.335 ms | 439.164 μs |
| translation_kernel | Float64 512^3 | — | — | — | — | 218.082 ms | 186.719 ms | 97.149 ms | 55.499 ms | — | — | — | — |
| translation_kernel | Float64 64^3 | 232.803 μs | 344.441 μs | 177.822 μs | 95.455 μs | 187.322 μs | 247.513 μs | 125.261 μs | 66.091 μs | — | — | 424.413 μs | 110.571 μs |

## transfer

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 28.940 ms | 14.161 ms | 7.801 ms | 4.725 ms | 20.903 ms | 11.035 ms | 5.923 ms | 3.418 ms | 2.280 ms | 4.864 ms | 774.794 μs | 213.792 μs |
| anterpolate! CatmullRom | Float32 256^3 | 445.713 ms | 228.844 ms | 123.921 ms | 78.168 ms | 172.994 ms | 90.522 ms | 45.443 ms | 23.543 ms | — | 17.932 ms | 3.198 ms | 2.891 ms |
| anterpolate! CatmullRom | Float32 512^3 | — | — | — | — | 2.937 s | 1.493 s | 769.387 ms | 463.944 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.249 ms | 1.874 ms | 1.208 ms | 913.384 μs | 2.522 ms | 1.453 ms | 935.048 μs | 651.737 μs | 116.972 μs | 2.057 ms | 434.815 μs | 101.241 μs |
| anterpolate! CatmullRom | Float64 128^3 | 34.542 ms | 16.274 ms | 8.112 ms | 4.894 ms | 22.205 ms | 11.591 ms | 6.102 ms | 3.552 ms | 2.691 ms | 4.862 ms | 881.660 μs | 229.492 μs |
| anterpolate! CatmullRom | Float64 256^3 | 552.915 ms | 290.910 ms | 166.179 ms | 117.563 ms | 268.223 ms | 133.029 ms | 66.629 ms | 36.261 ms | — | 19.810 ms | 4.031 ms | 4.672 ms |
| anterpolate! CatmullRom | Float64 512^3 | — | — | — | — | 3.375 s | 1.740 s | 905.468 ms | 562.442 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.425 ms | 1.926 ms | 1.277 ms | 954.485 μs | 2.534 ms | 1.497 ms | 985.917 μs | 699.667 μs | 185.312 μs | 2.004 ms | 356.139 μs | 131.041 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 206.639 ms | 103.232 ms | 53.744 ms | 30.000 ms | 160.057 ms | 80.548 ms | 40.657 ms | 21.705 ms | 12.241 ms | 15.478 ms | 3.480 ms | 978.920 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.514 s | 1.333 s | 796.348 ms | 531.881 ms | 1.282 s | 647.063 ms | 323.910 ms | 161.687 ms | — | 48.567 ms | 17.733 ms | 15.007 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 11.811 s | 5.947 s | 3.018 s | 1.727 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.599 ms | 13.313 ms | 8.357 ms | 5.699 ms | 19.885 ms | 10.615 ms | 6.457 ms | 4.341 ms | 486.825 μs | 5.959 ms | 1.345 ms | 317.903 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 231.324 ms | 111.720 ms | 56.905 ms | 31.151 ms | 160.526 ms | 80.556 ms | 40.588 ms | 21.591 ms | 13.808 ms | 16.564 ms | 4.326 ms | 1.166 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.830 s | 1.540 s | 962.001 ms | 675.882 ms | 1.408 s | 699.044 ms | 350.488 ms | 178.552 ms | — | 66.043 ms | 28.006 ms | 24.238 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 12.834 s | 6.550 s | 3.378 s | 2.160 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 25.461 ms | 13.667 ms | 8.610 ms | 5.857 ms | 19.933 ms | 10.756 ms | 6.549 ms | 4.415 ms | 825.268 μs | 5.503 ms | 1.808 ms | 329.663 μs |
| anterpolate! NUFFT | Float32 128^3 | 453.275 ms | 249.588 ms | 166.972 ms | 126.014 ms | 377.319 ms | 199.079 ms | 100.547 ms | 60.768 ms | 20.177 ms | 18.762 ms | 4.619 ms | 2.758 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.662 s | 2.590 s | 1.613 s | 1.206 s | 3.789 s | 2.019 s | 1.106 s | 671.440 ms | — | 120.799 ms | 32.116 ms | 28.431 ms |
| anterpolate! NUFFT | Float32 512^3 | — | — | — | — | 31.159 s | 16.524 s | 9.054 s | 5.738 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 34.030 ms | 18.389 ms | 11.864 ms | 8.462 ms | 27.011 ms | 14.621 ms | 8.741 ms | 5.998 ms | 1.989 ms | 6.296 ms | 1.556 ms | 424.464 μs |
| anterpolate! NUFFT | Float64 128^3 | 582.314 ms | 366.883 ms | 244.533 ms | 194.140 ms | 428.322 ms | 222.683 ms | 146.859 ms | 83.103 ms | 30.358 ms | 22.503 ms | 9.419 ms | 6.541 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.518 s | 3.190 s | 2.065 s | 1.649 s | 3.658 s | 2.038 s | 1.231 s | 868.124 ms | — | 160.735 ms | 75.186 ms | 58.208 ms |
| anterpolate! NUFFT | Float64 512^3 | — | — | — | — | 39.578 s | 21.844 s | 12.635 s | 8.488 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 41.043 ms | 22.676 ms | 15.325 ms | 11.878 ms | 33.374 ms | 18.117 ms | 10.605 ms | 7.037 ms | 3.892 ms | 8.203 ms | 2.551 ms | 821.478 μs |
| anterpolate! trilinear | Float32 128^3 | 4.622 ms | 2.326 ms | 1.425 ms | 934.458 μs | 4.689 ms | 2.563 ms | 1.476 ms | 861.290 μs | 460.884 μs | 2.018 ms | 399.236 μs | 82.721 μs |
| anterpolate! trilinear | Float32 256^3 | 90.598 ms | 49.168 ms | 28.838 ms | 22.504 ms | 41.525 ms | 22.336 ms | 11.774 ms | 6.456 ms | — | 6.631 ms | 935.853 μs | 727.077 μs |
| anterpolate! trilinear | Float32 512^3 | — | — | — | — | 741.842 ms | 377.838 ms | 202.287 ms | 126.348 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 495.629 μs | 323.836 μs | 226.273 μs | 176.552 μs | 370.281 μs | 228.722 μs | 168.271 μs | 127.111 μs | 70.080 μs | 1.565 ms | 307.708 μs | 64.750 μs |
| anterpolate! trilinear | Float64 128^3 | 5.575 ms | 2.810 ms | 1.660 ms | 1.144 ms | 6.072 ms | 3.223 ms | 1.826 ms | 1.144 ms | 596.666 μs | 1.980 ms | 394.307 μs | 95.541 μs |
| anterpolate! trilinear | Float64 256^3 | 98.538 ms | 56.188 ms | 38.006 ms | 30.037 ms | 72.794 ms | 37.486 ms | 19.633 ms | 11.356 ms | — | 6.838 ms | 986.761 μs | 1.111 ms |
| anterpolate! trilinear | Float64 512^3 | — | — | — | — | 785.284 ms | 404.915 ms | 214.327 ms | 136.693 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 519.589 μs | 362.857 μs | 268.310 μs | 211.923 μs | 379.424 μs | 261.103 μs | 176.771 μs | 132.701 μs | 83.721 μs | 1.554 ms | 319.743 μs | 84.761 μs |
| interpolate! CatmullRom | Float32 128^3 | 12.089 ms | 5.951 ms | 3.108 ms | 1.684 ms | 5.411 ms | 2.774 ms | 1.387 ms | 745.229 μs | 972.889 μs | 3.140 ms | 513.046 μs | 126.662 μs |
| interpolate! CatmullRom | Float32 256^3 | 302.879 ms | 156.419 ms | 83.584 ms | 53.267 ms | 53.358 ms | 28.718 ms | 14.096 ms | 6.787 ms | — | 14.577 ms | 1.580 ms | 868.989 μs |
| interpolate! CatmullRom | Float32 512^3 | — | — | — | — | 1.840 s | 922.747 ms | 472.532 ms | 277.530 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.336 ms | 711.866 μs | 437.869 μs | 300.388 μs | 625.643 μs | 329.964 μs | 199.582 μs | 133.971 μs | 101.321 μs | 1.724 ms | 376.135 μs | 79.331 μs |
| interpolate! CatmullRom | Float64 128^3 | 16.595 ms | 7.290 ms | 3.708 ms | 2.001 ms | 5.632 ms | 2.826 ms | 1.442 ms | 782.568 μs | 1.411 ms | 2.789 ms | 665.788 μs | 185.652 μs |
| interpolate! CatmullRom | Float64 256^3 | 330.742 ms | 173.228 ms | 101.047 ms | 66.240 ms | 152.641 ms | 75.175 ms | 37.847 ms | 20.063 ms | — | 12.939 ms | 2.020 ms | 1.683 ms |
| interpolate! CatmullRom | Float64 512^3 | — | — | — | — | 2.047 s | 1.048 s | 536.648 ms | 315.863 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.386 ms | 755.180 μs | 461.670 μs | 321.818 μs | 665.912 μs | 354.494 μs | 217.152 μs | 145.531 μs | 166.201 μs | 1.759 ms | 432.806 μs | 112.371 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 77.538 ms | 38.641 ms | 19.795 ms | 10.740 ms | 42.312 ms | 21.276 ms | 10.725 ms | 5.648 ms | 5.370 ms | 14.027 ms | 2.087 ms | 473.005 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.640 s | 901.758 ms | 561.171 ms | 355.760 ms | 344.308 ms | 191.978 ms | 93.734 ms | 46.191 ms | — | 30.216 ms | 10.730 ms | 4.724 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 5.486 s | 2.844 s | 1.483 s | 917.552 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.968 ms | 4.733 ms | 2.883 ms | 1.938 ms | 5.053 ms | 2.679 ms | 1.611 ms | 1.079 ms | 688.416 μs | 3.166 ms | 1.072 ms | 267.273 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 98.748 ms | 47.842 ms | 24.998 ms | 13.674 ms | 41.519 ms | 20.792 ms | 10.533 ms | 5.540 ms | 8.105 ms | 9.517 ms | 2.329 ms | 829.698 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.991 s | 1.134 s | 751.721 ms | 481.652 ms | 593.389 ms | 297.036 ms | 149.448 ms | 77.194 ms | — | 28.103 ms | 10.354 ms | 9.992 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 6.660 s | 3.564 s | 1.999 s | 1.224 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.170 ms | 4.977 ms | 2.998 ms | 2.024 ms | 5.276 ms | 2.831 ms | 1.680 ms | 1.116 ms | 911.428 μs | 3.595 ms | 1.429 ms | 329.963 μs |
| interpolate! NUFFT | Float32 128^3 | 347.500 ms | 203.706 ms | 137.004 ms | 112.535 ms | 261.826 ms | 144.349 ms | 83.616 ms | 46.048 ms | 12.723 ms | 16.422 ms | 3.783 ms | 1.895 ms |
| interpolate! NUFFT | Float32 256^3 | 3.874 s | 2.238 s | 1.475 s | 1.063 s | 2.995 s | 1.627 s | 934.083 ms | 603.367 ms | — | 72.243 ms | 25.429 ms | 17.639 ms |
| interpolate! NUFFT | Float32 512^3 | — | — | — | — | 24.851 s | 13.482 s | 7.702 s | 5.223 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 18.087 ms | 10.580 ms | 7.136 ms | 5.312 ms | 11.985 ms | 6.703 ms | 3.899 ms | 2.552 ms | 1.847 ms | 4.302 ms | 1.350 ms | 403.474 μs |
| interpolate! NUFFT | Float64 128^3 | 452.141 ms | 284.231 ms | 214.567 ms | 176.271 ms | 224.694 ms | 137.628 ms | 95.254 ms | 80.382 ms | 25.361 ms | 18.237 ms | 8.028 ms | 5.526 ms |
| interpolate! NUFFT | Float64 256^3 | 4.263 s | 2.553 s | 1.814 s | 1.465 s | 2.048 s | 1.254 s | 864.012 ms | 708.411 ms | — | 118.516 ms | 55.024 ms | 47.735 ms |
| interpolate! NUFFT | Float64 512^3 | — | — | — | — | 24.776 s | 14.252 s | 8.696 s | 9.590 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 24.593 ms | 15.853 ms | 11.858 ms | 9.597 ms | 17.424 ms | 9.764 ms | 6.097 ms | 4.046 ms | 3.417 ms | 6.116 ms | 2.315 ms | 937.779 μs |
| interpolate! trilinear | Float32 128^3 | 2.029 ms | 1.050 ms | 549.552 μs | 296.572 μs | 1.306 ms | 678.987 μs | 341.244 μs | 180.292 μs | 255.582 μs | 1.719 ms | 366.430 μs | 66.320 μs |
| interpolate! trilinear | Float32 256^3 | 59.612 ms | 31.528 ms | 16.597 ms | 10.000 ms | 14.100 ms | 7.407 ms | 3.698 ms | 1.771 ms | — | 3.594 ms | 535.992 μs | 246.083 μs |
| interpolate! trilinear | Float32 512^3 | — | — | — | — | 431.535 ms | 217.921 ms | 116.004 ms | 67.992 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 234.257 μs | 128.294 μs | 80.945 μs | 56.025 μs | 146.570 μs | 79.781 μs | 47.721 μs | 32.750 μs | 65.160 μs | 1.448 ms | 312.795 μs | 58.141 μs |
| interpolate! trilinear | Float64 128^3 | 2.641 ms | 1.283 ms | 657.885 μs | 363.000 μs | 1.358 ms | 702.358 μs | 346.133 μs | 190.992 μs | 325.503 μs | 1.772 ms | 336.686 μs | 82.311 μs |
| interpolate! trilinear | Float64 256^3 | 64.721 ms | 35.808 ms | 22.236 ms | 14.456 ms | 33.750 ms | 16.626 ms | 8.322 ms | 4.247 ms | — | 4.014 ms | 845.229 μs | 410.714 μs |
| interpolate! trilinear | Float64 512^3 | — | — | — | — | 444.580 ms | 228.105 ms | 125.352 ms | 67.220 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 244.280 μs | 135.084 μs | 83.822 μs | 58.437 μs | 161.391 μs | 86.641 μs | 49.500 μs | 33.680 μs | 65.930 μs | 1.530 ms | 155.672 μs | 70.791 μs |

## reductions

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.263 ms | 7.083 ms | 7.566 ms | 7.786 ms | 6.960 ms | 5.126 ms | 5.881 ms | 6.415 ms | 2.099 ms | 27.761 ms | 839.031 μs | 294.663 μs |
| co-spectrum vec.vec | Float32 256^3 | 66.852 ms | 49.480 ms | 45.365 ms | 42.410 ms | 55.740 ms | 37.019 ms | 32.067 ms | 31.172 ms | — | 97.666 ms | 2.655 ms | 948.300 μs |
| co-spectrum vec.vec | Float32 512^3 | — | — | — | — | 440.264 ms | 273.584 ms | 192.364 ms | 160.445 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.076 ms | 1.308 ms | 1.519 ms | 1.587 ms | 904.175 μs | 952.021 μs | 1.236 ms | 1.435 ms | 491.824 μs | 17.761 ms | 588.948 μs | 179.252 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.678 ms | 6.316 ms | 5.875 ms | 5.423 ms | 7.272 ms | 5.144 ms | 4.534 ms | 4.478 ms | 2.194 ms | 29.708 ms | 28.650 ms | 382.564 μs |
| co-spectrum vec.vec | Float64 256^3 | 70.996 ms | 50.569 ms | 37.153 ms | 30.218 ms | 59.121 ms | 37.217 ms | 26.817 ms | 22.983 ms | — | 109.563 ms | 65.238 ms | 1.386 ms |
| co-spectrum vec.vec | Float64 512^3 | — | — | — | — | 465.329 ms | 288.031 ms | 185.766 ms | 131.895 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.090 ms | 953.007 μs | 917.569 μs | 1.012 ms | 937.773 μs | 741.939 μs | 847.847 μs | 940.869 μs | 482.135 μs | 16.075 ms | 14.991 ms | 209.862 μs |
| cross-correlation vec.vec | Float32 128^3 | 43.424 ms | 41.255 ms | 37.979 ms | 37.074 ms | 38.504 ms | 33.502 ms | 25.337 ms | 22.910 ms | 5.891 ms | 43.640 ms | 1.660 ms | 805.128 μs |
| cross-correlation vec.vec | Float32 256^3 | 639.849 ms | 502.028 ms | 357.431 ms | 295.912 ms | 812.542 ms | 600.664 ms | 345.982 ms | 261.544 ms | — | 186.915 ms | 9.711 ms | 5.833 ms |
| cross-correlation vec.vec | Float32 512^3 | — | — | — | — | 8.035 s | 5.598 s | 3.082 s | 2.257 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.909 ms | 6.487 ms | 6.293 ms | 6.488 ms | 3.992 ms | 4.176 ms | 3.957 ms | 3.895 ms | 1.025 ms | 20.682 ms | 639.508 μs | 220.992 μs |
| cross-correlation vec.vec | Float64 128^3 | 86.193 ms | 68.910 ms | 57.258 ms | 44.975 ms | 79.715 ms | 61.407 ms | 41.593 ms | 34.604 ms | 9.144 ms | 52.055 ms | 45.585 ms | 2.083 ms |
| cross-correlation vec.vec | Float64 256^3 | 768.419 ms | 609.905 ms | 424.586 ms | 376.028 ms | 620.779 ms | 468.784 ms | 290.885 ms | 258.780 ms | — | 217.471 ms | 135.191 ms | 16.292 ms |
| cross-correlation vec.vec | Float64 512^3 | — | — | — | — | 4.818 s | 3.573 s | 2.222 s | 1.873 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 6.074 ms | 6.567 ms | 6.174 ms | 6.112 ms | 4.720 ms | 4.341 ms | 3.801 ms | 3.692 ms | 1.557 ms | 20.881 ms | 24.603 ms | 350.994 μs |
| inner spectral | Float32 128^3 | 1.678 ms | 1.641 ms | 1.709 ms | 1.616 ms | 533.624 μs | 529.646 μs | 538.735 μs | 524.826 μs | 669.926 μs | 2.049 ms | 581.033 μs | 241.773 μs |
| inner spectral | Float32 256^3 | 17.465 ms | 17.199 ms | 18.705 ms | 18.166 ms | 7.757 ms | 7.935 ms | 7.498 ms | 7.918 ms | — | 3.999 ms | 1.082 ms | 753.547 μs |
| inner spectral | Float32 512^3 | — | — | — | — | 80.806 ms | 80.640 ms | 79.881 ms | 80.578 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 150.309 μs | 152.802 μs | 150.041 μs | 153.956 μs | 87.440 μs | 89.571 μs | 98.970 μs | 98.431 μs | 275.972 μs | 1.780 ms | 526.140 μs | 190.302 μs |
| inner spectral | Float64 128^3 | 3.257 ms | 3.187 ms | 3.197 ms | 3.189 ms | 608.024 μs | 623.988 μs | 594.035 μs | 561.926 μs | 811.337 μs | 2.410 ms | 766.894 μs | 350.764 μs |
| inner spectral | Float64 256^3 | 27.816 ms | 28.026 ms | 28.065 ms | 28.147 ms | 16.200 ms | 16.287 ms | 16.331 ms | 16.754 ms | — | 7.953 ms | 2.174 ms | 1.224 ms |
| inner spectral | Float64 512^3 | — | — | — | — | 132.137 ms | 129.291 ms | 128.425 ms | 134.689 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 122.532 μs | 121.474 μs | 122.266 μs | 128.574 μs | 66.490 μs | 68.031 μs | 69.371 μs | 69.070 μs | 293.003 μs | 1.765 ms | 518.559 μs | 224.802 μs |
| inner vec.vec | Float32 128^3 | 1.278 ms | 1.275 ms | 1.346 ms | 1.286 ms | 311.142 μs | 311.033 μs | 324.893 μs | 310.464 μs | 308.353 μs | 1.623 ms | 264.045 μs | 107.591 μs |
| inner vec.vec | Float32 256^3 | 13.684 ms | 13.563 ms | 13.391 ms | 13.360 ms | 5.950 ms | 5.679 ms | 5.942 ms | 5.904 ms | — | 3.382 ms | 650.639 μs | 563.926 μs |
| inner vec.vec | Float32 512^3 | — | — | — | — | 56.778 ms | 56.346 ms | 56.345 ms | 57.442 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 66.271 μs | 66.667 μs | 66.309 μs | 67.193 μs | 38.360 μs | 38.490 μs | 38.280 μs | 38.710 μs | 98.731 μs | 1.278 ms | 250.252 μs | 76.211 μs |
| inner vec.vec | Float64 128^3 | 2.255 ms | 2.286 ms | 2.292 ms | 2.273 ms | 225.361 μs | 238.713 μs | 215.172 μs | 224.083 μs | 552.615 μs | 1.860 ms | 264.629 μs | 242.022 μs |
| inner vec.vec | Float64 256^3 | 23.368 ms | 23.570 ms | 22.645 ms | 23.069 ms | 13.005 ms | 13.011 ms | 13.048 ms | 13.063 ms | — | 5.634 ms | 1.408 ms | 1.058 ms |
| inner vec.vec | Float64 512^3 | — | — | — | — | 111.977 ms | 110.564 ms | 110.792 ms | 113.961 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 27.538 μs | 29.558 μs | 32.952 μs | 35.172 μs | 10.560 μs | 10.450 μs | 10.340 μs | 9.970 μs | 162.792 μs | 1.434 ms | 250.809 μs | 119.871 μs |
| integral scalar | Float32 128^3 | 113.400 μs | 108.417 μs | 110.182 μs | 113.181 μs | 59.491 μs | 62.251 μs | 64.781 μs | 60.051 μs | 228.932 μs | 1.318 ms | 498.427 μs | 95.561 μs |
| integral scalar | Float32 256^3 | 2.178 ms | 2.178 ms | 2.148 ms | 2.198 ms | 521.755 μs | 543.196 μs | 597.325 μs | 512.636 μs | — | 9.002 ms | 1.689 ms | 252.613 μs |
| integral scalar | Float32 512^3 | — | — | — | — | 11.007 ms | 11.546 ms | 10.773 ms | 11.677 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 10.911 μs | 10.766 μs | 10.747 μs | 11.064 μs | 5.837 μs | 6.214 μs | 6.862 μs | 6.898 μs | 95.301 μs | 1.534 ms | 335.134 μs | 81.371 μs |
| integral scalar | Float64 128^3 | 243.528 μs | 256.377 μs | 243.628 μs | 237.094 μs | 122.401 μs | 121.091 μs | 119.071 μs | 119.022 μs | 221.812 μs | 2.553 ms | 408.667 μs | 118.972 μs |
| integral scalar | Float64 256^3 | 5.271 ms | 4.816 ms | 5.071 ms | 5.087 ms | 1.956 ms | 1.975 ms | 2.253 ms | 2.033 ms | — | 10.817 ms | 2.011 ms | 267.822 μs |
| integral scalar | Float64 512^3 | — | — | — | — | 19.561 ms | 20.315 ms | 19.634 ms | 19.579 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.364 μs | 27.281 μs | 26.233 μs | 28.818 μs | 14.810 μs | 13.600 μs | 15.270 μs | 15.300 μs | 95.391 μs | 1.583 ms | 342.341 μs | 87.351 μs |
| integral spectral vec | Float32 128^3 | 67.985 ns | 68.105 ns | 68.078 ns | 68.363 ns | 69.039 ns | 69.221 ns | 74.474 ns | 74.652 ns | — | — | 317.457 μs | 48.471 μs |
| integral spectral vec | Float32 256^3 | 67.784 ns | 69.094 ns | 68.335 ns | 69.317 ns | 69.632 ns | 69.704 ns | 74.873 ns | 74.786 ns | — | — | 299.775 μs | 57.701 μs |
| integral spectral vec | Float32 512^3 | — | — | — | — | 70.799 ns | 70.124 ns | 75.805 ns | 75.503 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 67.887 ns | 67.971 ns | 68.011 ns | 67.882 ns | 70.851 ns | 69.090 ns | 74.447 ns | 76.141 ns | — | — | 316.532 μs | 47.490 μs |
| integral spectral vec | Float64 128^3 | 70.912 ns | 69.573 ns | 69.502 ns | 69.698 ns | 73.646 ns | 74.087 ns | 78.508 ns | 73.503 ns | — | — | 313.854 μs | 55.050 μs |
| integral spectral vec | Float64 256^3 | 74.535 ns | 69.957 ns | 71.417 ns | 70.402 ns | 76.777 ns | 74.590 ns | 78.921 ns | 74.309 ns | — | — | 162.397 μs | 51.080 μs |
| integral spectral vec | Float64 512^3 | — | — | — | — | 77.210 ns | 76.849 ns | 82.653 ns | 78.348 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 69.870 ns | 69.400 ns | 69.279 ns | 68.970 ns | 75.956 ns | 76.493 ns | 79.122 ns | 75.962 ns | — | — | 303.750 μs | 45.880 μs |
| l2norm vec | Float32 128^3 | 496.324 μs | 523.511 μs | 511.792 μs | 501.651 μs | 166.021 μs | 168.772 μs | 172.341 μs | 164.962 μs | 196.632 μs | 1.582 ms | 262.024 μs | 83.141 μs |
| l2norm vec | Float32 256^3 | 7.000 ms | 7.170 ms | 6.756 ms | 6.885 ms | 2.422 ms | 2.220 ms | 2.496 ms | 2.142 ms | — | 3.219 ms | 567.486 μs | 350.064 μs |
| l2norm vec | Float32 512^3 | — | — | — | — | 26.087 ms | 28.543 ms | 27.972 ms | 26.875 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 40.460 μs | 42.598 μs | 42.232 μs | 41.715 μs | 22.450 μs | 19.010 μs | 19.150 μs | 21.200 μs | 85.641 μs | 1.361 ms | 247.590 μs | 78.861 μs |
| l2norm vec | Float64 128^3 | 767.805 μs | 759.195 μs | 765.750 μs | 791.552 μs | 63.881 μs | 62.301 μs | 64.490 μs | 63.211 μs | 344.333 μs | 1.876 ms | 382.666 μs | 149.111 μs |
| l2norm vec | Float64 256^3 | 11.220 ms | 11.435 ms | 11.451 ms | 11.758 ms | 5.557 ms | 5.523 ms | 5.533 ms | 5.577 ms | — | 5.670 ms | 1.275 ms | 585.426 μs |
| l2norm vec | Float64 512^3 | — | — | — | — | 54.825 ms | 54.741 ms | 54.772 ms | 55.176 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 16.464 μs | 16.203 μs | 16.743 μs | 16.332 μs | 4.129 μs | 3.771 μs | 3.343 μs | 3.311 μs | 134.871 μs | 1.402 ms | 101.913 μs | 112.441 μs |
| lpnorm vec Inf | Float32 128^3 | 1.406 ms | 5.670 ms | 3.066 ms | 1.897 ms | 446.743 μs | 3.996 ms | 2.135 ms | 1.194 ms | 592.145 μs | 3.080 ms | 671.607 μs | 139.772 μs |
| lpnorm vec Inf | Float32 256^3 | 23.026 ms | 49.984 ms | 27.046 ms | 15.439 ms | 18.974 ms | 39.458 ms | 21.613 ms | 13.265 ms | — | 13.216 ms | 2.615 ms | 594.956 μs |
| lpnorm vec Inf | Float32 512^3 | — | — | — | — | 151.867 ms | 303.819 ms | 168.951 ms | 99.286 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 101.323 μs | 671.481 μs | 364.136 μs | 217.019 μs | 62.010 μs | 496.906 μs | 266.252 μs | 151.382 μs | 155.751 μs | 1.641 ms | 384.937 μs | 107.542 μs |
| lpnorm vec Inf | Float64 128^3 | 3.314 ms | 6.433 ms | 3.909 ms | 3.233 ms | 1.126 ms | 4.460 ms | 2.491 ms | 1.481 ms | 660.476 μs | 3.883 ms | 892.140 μs | 256.793 μs |
| lpnorm vec Inf | Float64 256^3 | 46.830 ms | 61.856 ms | 34.920 ms | 23.496 ms | 36.609 ms | 52.862 ms | 29.943 ms | 20.075 ms | — | 14.730 ms | 4.731 ms | 968.499 μs |
| lpnorm vec Inf | Float64 512^3 | — | — | — | — | 260.371 ms | 376.697 ms | 217.013 ms | 150.375 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 247.350 μs | 769.630 μs | 451.701 μs | 281.444 μs | 111.681 μs | 548.147 μs | 304.892 μs | 182.182 μs | 166.092 μs | 1.711 ms | 414.213 μs | 127.922 μs |
| maximum scalar | Float32 128^3 | 343.179 μs | 342.185 μs | 341.855 μs | 343.284 μs | 232.862 μs | 231.202 μs | 234.612 μs | 232.653 μs | 223.322 μs | 2.331 ms | 499.085 μs | 95.471 μs |
| maximum scalar | Float32 256^3 | 2.908 ms | 2.940 ms | 2.925 ms | 2.891 ms | 1.844 ms | 1.885 ms | 1.949 ms | 1.865 ms | — | 9.121 ms | 1.595 ms | 249.962 μs |
| maximum scalar | Float32 512^3 | — | — | — | — | 29.758 ms | 24.142 ms | 28.328 ms | 24.921 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 42.654 μs | 42.641 μs | 42.642 μs | 42.640 μs | 28.990 μs | 28.781 μs | 28.840 μs | 28.860 μs | 101.731 μs | 1.564 ms | 356.605 μs | 86.971 μs |
| maximum scalar | Float64 128^3 | 557.677 μs | 565.583 μs | 560.615 μs | 550.517 μs | 440.933 μs | 438.955 μs | 432.594 μs | 432.895 μs | 244.072 μs | 2.772 ms | 590.993 μs | 114.171 μs |
| maximum scalar | Float64 256^3 | 6.803 ms | 6.341 ms | 6.531 ms | 6.571 ms | 4.508 ms | 3.986 ms | 4.123 ms | 4.964 ms | — | 12.659 ms | 2.596 ms | 285.993 μs |
| maximum scalar | Float64 512^3 | — | — | — | — | 45.750 ms | 44.335 ms | 45.842 ms | 45.741 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 65.465 μs | 65.207 μs | 65.402 μs | 66.478 μs | 54.850 μs | 54.470 μs | 54.770 μs | 54.141 μs | 99.451 μs | 1.634 ms | 362.143 μs | 104.091 μs |
| maximum(norm) vec | Float32 128^3 | 1.857 ms | 1.850 ms | 1.856 ms | 1.856 ms | 774.086 μs | 774.119 μs | 772.847 μs | 774.509 μs | — | — | 528.932 μs | 109.321 μs |
| maximum(norm) vec | Float32 256^3 | 15.394 ms | 15.401 ms | 15.309 ms | 15.369 ms | 8.233 ms | 8.121 ms | 7.969 ms | 8.365 ms | — | — | 2.136 ms | 370.294 μs |
| maximum(norm) vec | Float32 512^3 | — | — | — | — | 65.477 ms | 59.642 ms | 65.768 ms | 58.948 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 225.513 μs | 225.213 μs | 225.051 μs | 224.996 μs | 97.090 μs | 98.381 μs | 96.671 μs | 95.931 μs | — | — | 350.398 μs | 80.721 μs |
| maximum(norm) vec | Float64 128^3 | 5.352 ms | 5.353 ms | 5.343 ms | 5.337 ms | 1.588 ms | 1.584 ms | 1.661 ms | 1.581 ms | — | — | 799.036 μs | 217.872 μs |
| maximum(norm) vec | Float64 256^3 | 43.808 ms | 43.733 ms | 43.304 ms | 43.411 ms | 15.747 ms | 15.787 ms | 15.631 ms | 15.572 ms | — | — | 4.228 ms | 1.048 ms |
| maximum(norm) vec | Float64 512^3 | — | — | — | — | 120.794 ms | 118.447 ms | 124.486 ms | 122.070 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 651.504 μs | 652.016 μs | 651.976 μs | 651.660 μs | 200.591 μs | 197.103 μs | 197.061 μs | 197.082 μs | — | — | 383.337 μs | 108.431 μs |
| mean spectral vec | Float32 128^3 | 70.324 ns | 70.922 ns | 70.948 ns | 71.788 ns | 72.323 ns | 72.606 ns | 77.072 ns | 73.402 ns | — | — | 308.514 μs | 50.831 μs |
| mean spectral vec | Float32 256^3 | 70.641 ns | 71.118 ns | 71.496 ns | 71.424 ns | 73.218 ns | 72.763 ns | 77.657 ns | 74.040 ns | — | — | 170.904 μs | 50.530 μs |
| mean spectral vec | Float32 512^3 | — | — | — | — | 74.688 ns | 73.273 ns | 79.743 ns | 75.911 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 70.581 ns | 70.389 ns | 70.261 ns | 71.427 ns | 73.884 ns | 72.298 ns | 76.975 ns | 72.991 ns | — | — | 315.433 μs | 47.261 μs |
| mean spectral vec | Float64 128^3 | 74.241 ns | 73.428 ns | 73.146 ns | 73.693 ns | 78.318 ns | 76.316 ns | 78.567 ns | 77.439 ns | — | — | 295.537 μs | 56.411 μs |
| mean spectral vec | Float64 256^3 | 74.676 ns | 74.353 ns | 78.820 ns | 73.872 ns | 80.413 ns | 77.991 ns | 79.609 ns | 78.080 ns | — | — | 295.185 μs | 46.460 μs |
| mean spectral vec | Float64 512^3 | — | — | — | — | 82.127 ns | 79.382 ns | 84.154 ns | 82.800 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 72.442 ns | 72.592 ns | 72.310 ns | 72.552 ns | 80.767 ns | 78.926 ns | 80.983 ns | 81.070 ns | — | — | 242.478 μs | 48.670 μs |
| mean vector | Float32 128^3 | 533.311 μs | 537.045 μs | 531.223 μs | 523.171 μs | 198.102 μs | 199.602 μs | 202.822 μs | 184.942 μs | 633.756 μs | 4.808 ms | 940.896 μs | 223.502 μs |
| mean vector | Float32 256^3 | 7.519 ms | 7.467 ms | 7.203 ms | 7.407 ms | 3.226 ms | 3.205 ms | 3.399 ms | 2.938 ms | — | 16.657 ms | 5.236 ms | 1.272 ms |
| mean vector | Float32 512^3 | — | — | — | — | 33.254 ms | 34.358 ms | 34.750 ms | 32.489 ms | — | — | — | — |
| mean vector | Float32 64^3 | 42.235 μs | 41.908 μs | 42.298 μs | 45.238 μs | 24.710 μs | 26.321 μs | 25.941 μs | 24.260 μs | 162.362 μs | 1.846 ms | 403.682 μs | 99.041 μs |
| mean vector | Float64 128^3 | 1.585 ms | 1.570 ms | 1.650 ms | 1.602 ms | 401.143 μs | 427.075 μs | 402.634 μs | 391.524 μs | 657.486 μs | 5.195 ms | 1.043 ms | 258.562 μs |
| mean vector | Float64 256^3 | 15.115 ms | 14.689 ms | 15.052 ms | 15.146 ms | 8.386 ms | 8.242 ms | 7.420 ms | 7.904 ms | — | 17.799 ms | 6.222 ms | 1.412 ms |
| mean vector | Float64 512^3 | — | — | — | — | 53.720 ms | 58.682 ms | 59.129 ms | 55.164 ms | — | — | — | — |
| mean vector | Float64 64^3 | 82.340 μs | 82.596 μs | 82.762 μs | 82.817 μs | 45.871 μs | 45.791 μs | 45.991 μs | 45.821 μs | 156.311 μs | 1.913 ms | 397.329 μs | 117.412 μs |
| mean(det) tensor | Float32 128^3 | 2.470 ms | 2.452 ms | 2.492 ms | 2.479 ms | 773.906 μs | 786.189 μs | 740.177 μs | 781.319 μs | — | — | 606.174 μs | 215.592 μs |
| mean(det) tensor | Float32 256^3 | 24.879 ms | 24.599 ms | 24.749 ms | 25.095 ms | 15.885 ms | 15.888 ms | 15.826 ms | 15.512 ms | — | — | 2.755 ms | 826.538 μs |
| mean(det) tensor | Float32 512^3 | — | — | — | — | 106.638 ms | 111.932 ms | 106.105 ms | 106.892 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 101.867 μs | 101.918 μs | 101.133 μs | 102.115 μs | 66.920 μs | 67.241 μs | 67.441 μs | 67.261 μs | — | — | 369.239 μs | 88.281 μs |
| mean(det) tensor | Float64 128^3 | 5.413 ms | 5.411 ms | 5.319 ms | 5.416 ms | 2.513 ms | 2.498 ms | 2.548 ms | 2.559 ms | — | — | 780.511 μs | 298.923 μs |
| mean(det) tensor | Float64 256^3 | 48.133 ms | 49.618 ms | 49.772 ms | 48.437 ms | 30.781 ms | 30.252 ms | 30.201 ms | 26.647 ms | — | — | 4.115 ms | 1.528 ms |
| mean(det) tensor | Float64 512^3 | — | — | — | — | 221.331 ms | 216.071 ms | 201.309 ms | 248.915 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 229.834 μs | 226.271 μs | 229.621 μs | 229.020 μs | 130.060 μs | 130.102 μs | 133.781 μs | 129.711 μs | — | — | 385.327 μs | 109.861 μs |
| mean(norm) vec | Float32 128^3 | 1.598 ms | 1.601 ms | 1.596 ms | 1.594 ms | 607.134 μs | 597.137 μs | 609.865 μs | 609.007 μs | — | — | 532.216 μs | 107.991 μs |
| mean(norm) vec | Float32 256^3 | 13.189 ms | 13.166 ms | 13.200 ms | 13.130 ms | 7.136 ms | 7.041 ms | 7.121 ms | 7.422 ms | — | — | 2.087 ms | 383.534 μs |
| mean(norm) vec | Float32 512^3 | — | — | — | — | 58.109 ms | 53.870 ms | 58.826 ms | 54.483 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 193.056 μs | 192.968 μs | 192.997 μs | 192.960 μs | 74.930 μs | 74.891 μs | 75.811 μs | 75.520 μs | — | — | 357.547 μs | 90.201 μs |
| mean(norm) vec | Float64 128^3 | 5.284 ms | 5.284 ms | 5.275 ms | 5.175 ms | 1.433 ms | 1.443 ms | 1.438 ms | 1.436 ms | — | — | 719.008 μs | 219.322 μs |
| mean(norm) vec | Float64 256^3 | 43.072 ms | 43.303 ms | 42.917 ms | 42.675 ms | 14.675 ms | 14.220 ms | 14.442 ms | 14.084 ms | — | — | 3.609 ms | 938.109 μs |
| mean(norm) vec | Float64 512^3 | — | — | — | — | 112.756 ms | 108.596 ms | 117.833 ms | 108.942 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 644.449 μs | 645.469 μs | 644.414 μs | 632.472 μs | 178.200 μs | 178.592 μs | 178.611 μs | 177.851 μs | — | — | 378.522 μs | 120.372 μs |
| mean(tr) tensor | Float32 128^3 | 395.648 μs | 400.391 μs | 417.426 μs | 394.809 μs | 187.361 μs | 197.062 μs | 203.582 μs | 197.582 μs | — | — | 494.486 μs | 110.021 μs |
| mean(tr) tensor | Float32 256^3 | 6.788 ms | 6.819 ms | 6.766 ms | 6.775 ms | 3.213 ms | 3.258 ms | 3.243 ms | 3.095 ms | — | — | 1.921 ms | 365.144 μs |
| mean(tr) tensor | Float32 512^3 | — | — | — | — | 33.350 ms | 33.331 ms | 33.246 ms | 33.869 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 35.425 μs | 34.565 μs | 34.820 μs | 34.552 μs | 25.260 μs | 25.390 μs | 24.390 μs | 24.590 μs | — | — | 358.443 μs | 82.381 μs |
| mean(tr) tensor | Float64 128^3 | 1.330 ms | 1.320 ms | 1.339 ms | 1.327 ms | 362.892 μs | 359.724 μs | 405.963 μs | 393.604 μs | — | — | 582.415 μs | 167.502 μs |
| mean(tr) tensor | Float64 256^3 | 13.692 ms | 13.983 ms | 13.790 ms | 13.851 ms | 7.123 ms | 6.725 ms | 6.989 ms | 6.656 ms | — | — | 2.349 ms | 579.706 μs |
| mean(tr) tensor | Float64 512^3 | — | — | — | — | 77.127 ms | 73.489 ms | 66.408 ms | 78.448 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 70.185 μs | 68.289 μs | 67.845 μs | 67.982 μs | 50.180 μs | 43.280 μs | 42.761 μs | 49.151 μs | — | — | 310.224 μs | 91.271 μs |
| radial_correlation vec | Float32 128^3 | 41.163 ms | 40.545 ms | 36.544 ms | 38.080 ms | 35.931 ms | 32.811 ms | 25.437 ms | 22.747 ms | 5.783 ms | 42.875 ms | 1.617 ms | 625.506 μs |
| radial_correlation vec | Float32 256^3 | 623.422 ms | 481.016 ms | 348.134 ms | 293.562 ms | 791.683 ms | 590.954 ms | 344.528 ms | 259.971 ms | — | 185.439 ms | 9.481 ms | 5.606 ms |
| radial_correlation vec | Float32 512^3 | — | — | — | — | 7.876 s | 5.572 s | 3.063 s | 2.219 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.612 ms | 6.396 ms | 6.164 ms | 6.363 ms | 3.659 ms | 4.107 ms | 3.848 ms | 3.797 ms | 1.010 ms | 19.917 ms | 677.607 μs | 225.762 μs |
| radial_correlation vec | Float64 128^3 | 83.653 ms | 71.915 ms | 56.215 ms | 41.289 ms | 74.712 ms | 59.526 ms | 41.173 ms | 33.373 ms | 9.025 ms | 52.060 ms | 45.597 ms | 2.024 ms |
| radial_correlation vec | Float64 256^3 | 753.759 ms | 602.903 ms | 417.684 ms | 378.734 ms | 583.844 ms | 463.798 ms | 299.774 ms | 253.292 ms | — | 219.151 ms | 136.364 ms | 14.554 ms |
| radial_correlation vec | Float64 512^3 | — | — | — | — | 4.606 s | 3.485 s | 2.180 s | 1.835 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.844 ms | 6.195 ms | 5.976 ms | 5.827 ms | 4.372 ms | 4.273 ms | 3.737 ms | 3.543 ms | 1.413 ms | 21.203 ms | 23.962 ms | 353.413 μs |
| radial_spectrum vec | Float32 128^3 | 7.677 ms | 6.451 ms | 8.022 ms | 8.200 ms | 6.326 ms | 4.868 ms | 5.765 ms | 6.047 ms | 1.415 ms | 27.166 ms | 821.492 μs | 289.963 μs |
| radial_spectrum vec | Float32 256^3 | 61.645 ms | 48.585 ms | 48.479 ms | 42.703 ms | 50.103 ms | 33.708 ms | 31.106 ms | 28.853 ms | — | 96.772 ms | 2.468 ms | 943.990 μs |
| radial_spectrum vec | Float32 512^3 | — | — | — | — | 399.615 ms | 238.731 ms | 179.939 ms | 154.899 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 997.899 μs | 1.352 ms | 1.569 ms | 1.622 ms | 821.234 μs | 922.870 μs | 1.160 ms | 1.327 ms | 344.443 μs | 16.995 ms | 559.122 μs | 179.882 μs |
| radial_spectrum vec | Float64 128^3 | 7.692 ms | 6.821 ms | 6.225 ms | 5.635 ms | 6.554 ms | 4.613 ms | 4.407 ms | 4.515 ms | 1.515 ms | 29.791 ms | 27.835 ms | 371.284 μs |
| radial_spectrum vec | Float64 256^3 | 62.834 ms | 46.484 ms | 35.375 ms | 30.287 ms | 51.974 ms | 31.974 ms | 25.275 ms | 23.016 ms | — | 110.504 ms | 65.951 ms | 1.371 ms |
| radial_spectrum vec | Float64 512^3 | — | — | — | — | 416.346 ms | 253.613 ms | 163.594 ms | 124.455 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 1.001 ms | 753.724 μs | 1.048 ms | 1.108 ms | 850.683 μs | 687.918 μs | 840.217 μs | 923.189 μs | 380.613 μs | 16.740 ms | 14.885 ms | 205.902 μs |
| weighted_inner vec | Float32 128^3 | 12.769 ms | 12.743 ms | 12.759 ms | 12.619 ms | 10.383 ms | 10.317 ms | 10.335 ms | 10.295 ms | — | — | 781.489 μs | 143.411 μs |
| weighted_inner vec | Float32 256^3 | 101.316 ms | 101.074 ms | 100.560 ms | 100.045 ms | 81.461 ms | 81.295 ms | 81.467 ms | 81.387 ms | — | — | 3.664 ms | 641.996 μs |
| weighted_inner vec | Float32 512^3 | — | — | — | — | 647.211 ms | 645.667 ms | 646.857 ms | 647.293 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.629 ms | 1.627 ms | 1.633 ms | 1.608 ms | 1.281 ms | 1.336 ms | 1.282 ms | 1.283 ms | — | — | 435.151 μs | 95.561 μs |
| weighted_inner vec | Float64 128^3 | 13.922 ms | 13.913 ms | 13.689 ms | 13.752 ms | 10.935 ms | 10.942 ms | 10.913 ms | 10.896 ms | — | — | 895.200 μs | 200.502 μs |
| weighted_inner vec | Float64 256^3 | 112.122 ms | 112.189 ms | 110.242 ms | 112.406 ms | 85.758 ms | 85.963 ms | 85.775 ms | 85.669 ms | — | — | 4.606 ms | 1.067 ms |
| weighted_inner vec | Float64 512^3 | — | — | — | — | 686.822 ms | 680.639 ms | 682.631 ms | 682.962 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.724 ms | 1.725 ms | 1.713 ms | 1.727 ms | 1.357 ms | 1.427 ms | 1.414 ms | 1.350 ms | — | — | 427.115 μs | 116.212 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.891 ms | 12.754 ms | 12.818 ms | 12.588 ms | 10.333 ms | 10.373 ms | 10.336 ms | 10.341 ms | — | — | 785.379 μs | 161.362 μs |
| weighted_inner vec.vec | Float32 256^3 | 101.369 ms | 100.652 ms | 101.275 ms | 100.337 ms | 81.585 ms | 81.409 ms | 81.591 ms | 81.279 ms | — | — | 3.636 ms | 840.549 μs |
| weighted_inner vec.vec | Float32 512^3 | — | — | — | — | 647.535 ms | 646.426 ms | 648.375 ms | 647.116 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.647 ms | 1.629 ms | 1.638 ms | 1.597 ms | 1.283 ms | 1.342 ms | 1.306 ms | 1.298 ms | — | — | 393.354 μs | 98.311 μs |
| weighted_inner vec.vec | Float64 128^3 | 14.416 ms | 14.195 ms | 14.171 ms | 13.930 ms | 10.923 ms | 10.983 ms | 10.942 ms | 10.908 ms | — | — | 887.918 μs | 259.593 μs |
| weighted_inner vec.vec | Float64 256^3 | 114.884 ms | 114.588 ms | 114.138 ms | 113.243 ms | 86.154 ms | 86.217 ms | 86.084 ms | 86.092 ms | — | — | 4.631 ms | 1.535 ms |
| weighted_inner vec.vec | Float64 512^3 | — | — | — | — | 683.560 ms | 683.174 ms | 682.652 ms | 684.687 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.772 ms | 1.731 ms | 1.723 ms | 1.733 ms | 1.410 ms | 1.446 ms | 1.427 ms | 1.395 ms | — | — | 443.334 μs | 106.461 μs |

