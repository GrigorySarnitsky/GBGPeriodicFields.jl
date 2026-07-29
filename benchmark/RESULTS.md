# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-07-29 at commit `6b4715e9` on Julia 1.12.6, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–256³) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, pre-swap, 64³/128³ only); **RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, pre-swap, 64³–256³); **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). Each office box was upgraded in place, the pre-swap card kept for the record: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX (both ROCm). The pre-swap archive columns (GTX 1070, RX 6700 XT) keep their pre-rewrite measurements — retired hardware is not re-swept; every live column (both CPUs, RX 7900 XTX, RTX 5070 Ti) is measured at the decision-38/39 rewrite. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `48b6254a @ 2026-07-22`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8; `5934a78c @ 2026-07-22`: GPU 7900XTX; `66ce3186 @ 2026-07-29`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8; `6b4715e9 @ 2026-07-29`: GPU 5070TI; unstamped (vintage in the prose above): GPU 1070, GPU 6700XT. ~10% jitter.

## fft

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 4.029 ms | 2.979 ms | 2.144 ms | 2.286 ms | 2.771 ms | 1.477 ms | 839.518 μs | 546.426 μs | — | — | — | — |
| to_physical scalar measure | Float32 256^3 | 70.669 ms | 39.135 ms | 41.008 ms | 38.313 ms | 34.606 ms | 21.723 ms | 14.555 ms | 12.274 ms | — | — | — | — |
| to_physical scalar measure | Float32 512^3 | — | — | — | — | 301.261 ms | 188.250 ms | 146.140 ms | 134.079 ms | — | — | — | — |
| to_physical scalar measure | Float32 64^3 | 379.762 μs | 239.143 μs | 166.345 μs | 174.205 μs | 278.363 μs | 160.021 μs | 96.851 μs | 66.201 μs | — | — | — | — |
| to_physical scalar measure | Float64 128^3 | 6.339 ms | 5.666 ms | 5.246 ms | 4.657 ms | 4.252 ms | 2.466 ms | 1.695 ms | 1.369 ms | — | — | — | — |
| to_physical scalar measure | Float64 256^3 | 130.934 ms | 77.228 ms | 81.269 ms | 80.228 ms | 65.910 ms | 44.201 ms | 32.812 ms | 38.714 ms | — | — | — | — |
| to_physical scalar measure | Float64 512^3 | — | — | — | — | 847.888 ms | 585.711 ms | 457.081 ms | 420.037 ms | — | — | — | — |
| to_physical scalar measure | Float64 64^3 | 550.138 μs | 384.916 μs | 254.230 μs | 269.289 μs | 362.134 μs | 210.253 μs | 126.521 μs | 96.131 μs | — | — | — | — |
| to_physical scalar | Float32 128^3 | 5.090 ms | 3.355 ms | 2.501 ms | 2.307 ms | 4.587 ms | 2.421 ms | 1.287 ms | 832.009 μs | 788.067 μs | 2.421 ms | 1.261 ms | 118.631 μs |
| to_physical scalar | Float32 256^3 | 121.444 ms | 68.555 ms | 51.504 ms | 42.019 ms | 172.773 ms | 90.768 ms | 49.577 ms | 30.131 ms | — | 7.945 ms | 2.307 ms | 1.100 ms |
| to_physical scalar | Float32 512^3 | — | — | — | — | 1.967 s | 1.043 s | 554.527 ms | 330.952 ms | — | — | 13.398 ms | — |
| to_physical scalar | Float32 64^3 | 393.312 μs | 254.738 μs | 177.742 μs | 169.864 μs | 319.683 μs | 179.232 μs | 103.091 μs | 69.260 μs | 124.402 μs | 1.497 ms | 1.071 ms | 105.531 μs |
| to_physical scalar | Float64 128^3 | 8.120 ms | 5.823 ms | 4.940 ms | 4.470 ms | 10.437 ms | 5.683 ms | 3.173 ms | 1.923 ms | 1.905 ms | 3.750 ms | 1.646 ms | 492.775 μs |
| to_physical scalar | Float64 256^3 | 153.418 ms | 86.677 ms | 84.769 ms | 78.209 ms | 84.159 ms | 49.964 ms | 35.778 ms | 43.566 ms | — | 14.463 ms | 5.748 ms | 3.864 ms |
| to_physical scalar | Float64 512^3 | — | — | — | — | 947.514 ms | 622.402 ms | 463.545 ms | 419.657 ms | — | — | — | — |
| to_physical scalar | Float64 64^3 | 702.253 μs | 432.399 μs | 307.892 μs | 258.256 μs | 538.516 μs | 288.363 μs | 169.121 μs | 116.862 μs | 331.873 μs | 1.784 ms | 992.328 μs | 136.922 μs |
| to_physical vector measure | Float32 128^3 | 12.766 ms | 9.673 ms | 8.916 ms | 7.915 ms | 9.564 ms | 5.961 ms | 3.763 ms | 3.260 ms | — | — | — | — |
| to_physical vector measure | Float32 256^3 | 214.079 ms | 158.244 ms | 131.321 ms | 124.027 ms | 121.312 ms | 84.491 ms | 55.226 ms | 50.612 ms | — | — | — | — |
| to_physical vector measure | Float32 512^3 | — | — | — | — | 1.434 s | 952.206 ms | 699.305 ms | 619.528 ms | — | — | — | — |
| to_physical vector measure | Float32 64^3 | 1.243 ms | 846.687 μs | 565.090 μs | 477.502 μs | 871.148 μs | 496.705 μs | 292.863 μs | 252.142 μs | — | — | — | — |
| to_physical vector measure | Float64 128^3 | 39.710 ms | 19.225 ms | 24.054 ms | 28.588 ms | 24.103 ms | 17.643 ms | 14.805 ms | 13.511 ms | — | — | — | — |
| to_physical vector measure | Float64 256^3 | 394.501 ms | 287.104 ms | 246.423 ms | 233.583 ms | 318.405 ms | 220.188 ms | 172.624 ms | 153.602 ms | — | — | — | — |
| to_physical vector measure | Float64 512^3 | — | — | — | — | 2.510 s | 1.777 s | 1.356 s | 1.254 s | — | — | — | — |
| to_physical vector measure | Float64 64^3 | 2.216 ms | 1.775 ms | 1.270 ms | 1.164 ms | 1.121 ms | 685.637 μs | 419.404 μs | 346.564 μs | — | — | — | — |
| to_physical vector | Float32 128^3 | 15.103 ms | 11.836 ms | 8.416 ms | 7.502 ms | 14.785 ms | 10.631 ms | 5.474 ms | 4.078 ms | 2.507 ms | 4.595 ms | 1.724 ms | 301.483 μs |
| to_physical vector | Float32 256^3 | 365.291 ms | 269.022 ms | 173.624 ms | 151.640 ms | 526.709 ms | 360.792 ms | 191.834 ms | 138.369 ms | — | 14.844 ms | 5.773 ms | 3.490 ms |
| to_physical vector | Float32 512^3 | — | — | — | — | 6.314 s | 4.333 s | 2.341 s | 1.664 s | — | — | 51.336 ms | — |
| to_physical vector | Float32 64^3 | 1.306 ms | 1.045 ms | 596.992 μs | 550.376 μs | 1.020 ms | 676.267 μs | 320.743 μs | 217.272 μs | 380.054 μs | 1.776 ms | 1.186 ms | 111.631 μs |
| to_physical vector | Float64 128^3 | 46.428 ms | 20.507 ms | 26.548 ms | 27.522 ms | 42.778 ms | 30.733 ms | 20.154 ms | 16.941 ms | 5.630 ms | 8.090 ms | 2.788 ms | 1.472 ms |
| to_physical vector | Float64 256^3 | 460.818 ms | 358.235 ms | 260.213 ms | 241.545 ms | 358.862 ms | 272.757 ms | 175.555 ms | 158.633 ms | — | 22.812 ms | 13.720 ms | 11.384 ms |
| to_physical vector | Float64 512^3 | — | — | — | — | 2.781 s | 2.147 s | 1.413 s | 1.288 s | — | — | — | — |
| to_physical vector | Float64 64^3 | 2.619 ms | 2.147 ms | 1.646 ms | 1.216 ms | 1.710 ms | 1.148 ms | 574.486 μs | 478.295 μs | 811.437 μs | 2.301 ms | 1.271 ms | 213.742 μs |
| to_spectral scalar measure | Float32 128^3 | 3.676 ms | 2.364 ms | 1.542 ms | 1.608 ms | 2.735 ms | 1.481 ms | 797.328 μs | 618.696 μs | — | — | — | — |
| to_spectral scalar measure | Float32 256^3 | 64.792 ms | 32.427 ms | 35.643 ms | 32.348 ms | 37.175 ms | 21.246 ms | 13.865 ms | 11.634 ms | — | — | — | — |
| to_spectral scalar measure | Float32 512^3 | — | — | — | — | 316.055 ms | 178.127 ms | 116.549 ms | 102.449 ms | — | — | — | — |
| to_spectral scalar measure | Float32 64^3 | 365.235 μs | 209.243 μs | 132.354 μs | 137.319 μs | 276.013 μs | 148.781 μs | 86.221 μs | 57.191 μs | — | — | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.417 ms | 4.397 ms | 3.789 ms | 3.542 ms | 4.434 ms | 2.513 ms | 1.382 ms | 1.392 ms | — | — | — | — |
| to_spectral scalar measure | Float64 256^3 | 125.027 ms | 67.875 ms | 71.203 ms | 65.713 ms | 62.564 ms | 37.573 ms | 27.915 ms | 29.622 ms | — | — | — | — |
| to_spectral scalar measure | Float64 512^3 | — | — | — | — | 757.252 ms | 483.272 ms | 388.635 ms | 340.945 ms | — | — | — | — |
| to_spectral scalar measure | Float64 64^3 | 488.909 μs | 307.927 μs | 233.393 μs | 155.459 μs | 340.093 μs | 190.742 μs | 108.041 μs | 74.271 μs | — | — | — | — |
| to_spectral scalar | Float32 128^3 | 4.631 ms | 2.783 ms | 1.829 ms | 1.359 ms | 4.503 ms | 2.513 ms | 1.313 ms | 756.778 μs | 488.254 μs | 2.072 ms | 1.113 ms | 87.881 μs |
| to_spectral scalar | Float32 256^3 | 116.450 ms | 64.693 ms | 48.096 ms | 36.889 ms | 170.777 ms | 87.635 ms | 47.496 ms | 27.994 ms | — | 5.009 ms | 1.905 ms | 736.957 μs |
| to_spectral scalar | Float32 512^3 | — | — | — | — | 1.919 s | 983.193 ms | 517.525 ms | 295.528 ms | — | — | 9.591 ms | — |
| to_spectral scalar | Float32 64^3 | 372.359 μs | 214.769 μs | 131.392 μs | 113.455 μs | 304.893 μs | 166.092 μs | 92.301 μs | 58.291 μs | 89.181 μs | 1.538 ms | 1.110 ms | 73.201 μs |
| to_spectral scalar | Float64 128^3 | 7.266 ms | 5.156 ms | 3.900 ms | 3.492 ms | 10.570 ms | 5.630 ms | 3.107 ms | 1.822 ms | 1.501 ms | 3.125 ms | 1.651 ms | 435.604 μs |
| to_spectral scalar | Float64 256^3 | 174.719 ms | 98.673 ms | 79.881 ms | 67.152 ms | 175.685 ms | 93.436 ms | 52.383 ms | 51.641 ms | — | 12.871 ms | 5.179 ms | 3.125 ms |
| to_spectral scalar | Float64 512^3 | — | — | — | — | 1.726 s | 972.463 ms | 605.168 ms | 451.730 ms | — | — | — | — |
| to_spectral scalar | Float64 64^3 | 660.845 μs | 375.644 μs | 246.524 μs | 187.733 μs | 516.395 μs | 274.773 μs | 153.902 μs | 96.761 μs | 265.683 μs | 1.745 ms | 1.077 ms | 117.361 μs |
| to_spectral vector measure | Float32 128^3 | 11.048 ms | 7.840 ms | 6.309 ms | 5.676 ms | 10.363 ms | 6.141 ms | 3.827 ms | 2.901 ms | — | — | — | — |
| to_spectral vector measure | Float32 256^3 | 194.942 ms | 138.599 ms | 108.318 ms | 104.246 ms | 123.631 ms | 75.484 ms | 46.347 ms | 42.381 ms | — | — | — | — |
| to_spectral vector measure | Float32 512^3 | — | — | — | — | 1.409 s | 902.880 ms | 639.989 ms | 531.902 ms | — | — | — | — |
| to_spectral vector measure | Float32 64^3 | 1.133 ms | 709.014 μs | 489.066 μs | 410.465 μs | 877.818 μs | 491.135 μs | 254.992 μs | 199.572 μs | — | — | — | — |
| to_spectral vector measure | Float64 128^3 | 36.748 ms | 15.038 ms | 18.304 ms | 13.894 ms | 25.286 ms | 18.055 ms | 14.785 ms | 8.312 ms | — | — | — | — |
| to_spectral vector measure | Float64 256^3 | 378.151 ms | 266.528 ms | 209.729 ms | 202.722 ms | 287.290 ms | 196.781 ms | 147.447 ms | 131.883 ms | — | — | — | — |
| to_spectral vector measure | Float64 512^3 | — | — | — | — | 2.198 s | 1.477 s | 1.158 s | 1.020 s | — | — | — | — |
| to_spectral vector measure | Float64 64^3 | 1.673 ms | 1.521 ms | 887.037 μs | 648.760 μs | 1.067 ms | 640.007 μs | 367.304 μs | 275.943 μs | — | — | — | — |
| to_spectral vector | Float32 128^3 | 14.075 ms | 9.864 ms | 6.814 ms | 5.884 ms | 15.193 ms | 10.604 ms | 5.295 ms | 3.985 ms | 1.355 ms | 3.183 ms | 1.354 ms | 202.122 μs |
| to_spectral vector | Float32 256^3 | 353.409 ms | 258.328 ms | 153.782 ms | 128.389 ms | 518.852 ms | 350.790 ms | 180.824 ms | 130.515 ms | — | 11.819 ms | 3.512 ms | 2.231 ms |
| to_spectral vector | Float32 512^3 | — | — | — | — | 6.274 s | 4.288 s | 2.253 s | 1.583 s | — | — | 20.305 ms | — |
| to_spectral vector | Float32 64^3 | 1.296 ms | 931.449 μs | 509.295 μs | 432.093 μs | 951.280 μs | 654.447 μs | 290.983 μs | 183.182 μs | 230.522 μs | 1.566 ms | 924.065 μs | 82.470 μs |
| to_spectral vector | Float64 128^3 | 43.494 ms | 18.891 ms | 23.457 ms | 13.411 ms | 42.821 ms | 31.667 ms | 19.722 ms | 12.208 ms | 4.144 ms | 6.538 ms | 2.420 ms | 1.178 ms |
| to_spectral vector | Float64 256^3 | 515.584 ms | 385.138 ms | 244.471 ms | 223.678 ms | 632.671 ms | 450.117 ms | 257.795 ms | 202.380 ms | — | 20.041 ms | 11.730 ms | 9.214 ms |
| to_spectral vector | Float64 512^3 | — | — | — | — | 5.103 s | 3.630 s | 2.044 s | 1.608 s | — | — | — | — |
| to_spectral vector | Float64 64^3 | 2.288 ms | 1.711 ms | 1.039 ms | 825.169 μs | 1.571 ms | 1.088 ms | 518.435 μs | 348.943 μs | 596.836 μs | 2.151 ms | 1.215 ms | 193.602 μs |

## algebra

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 415.446 μs | 232.867 μs | 171.971 μs | 72.717 μs | 162.582 μs | 84.421 μs | 45.281 μs | 37.121 μs | 351.303 μs | 1.943 ms | 1.146 ms | 77.671 μs |
| add! scalar | Float32 256^3 | 8.457 ms | 7.574 ms | 5.893 ms | 5.483 ms | 3.588 ms | 3.018 ms | 2.923 ms | 2.982 ms | — | 6.480 ms | 1.935 ms | 344.823 μs |
| add! scalar | Float32 512^3 | — | — | — | — | 40.949 ms | 36.473 ms | 36.592 ms | 37.172 ms | — | — | 7.478 ms | — |
| add! scalar | Float32 64^3 | 43.141 μs | 21.824 μs | 10.651 μs | 8.520 μs | 21.061 μs | 12.690 μs | 6.850 μs | 6.775 μs | 85.391 μs | 1.599 ms | 1.040 ms | 65.061 μs |
| add! scalar | Float64 128^3 | 1.551 ms | 1.347 ms | 1.009 ms | 866.257 μs | 321.433 μs | 164.522 μs | 84.831 μs | 72.590 μs | 354.693 μs | 2.024 ms | 1.185 ms | 88.731 μs |
| add! scalar | Float64 256^3 | 17.701 ms | 15.946 ms | 12.391 ms | 11.679 ms | 10.527 ms | 8.715 ms | 9.109 ms | 8.878 ms | — | 5.550 ms | 1.863 ms | 566.806 μs |
| add! scalar | Float64 512^3 | — | — | — | — | 83.685 ms | 72.942 ms | 73.354 ms | 75.448 ms | — | — | — | — |
| add! scalar | Float64 64^3 | 85.390 μs | 49.484 μs | 21.892 μs | 16.987 μs | 40.241 μs | 22.481 μs | 12.090 μs | 9.830 μs | 83.741 μs | 1.494 ms | 1.042 ms | 57.260 μs |
| combine! vec | Float32 128^3 | 2.791 ms | 2.491 ms | 1.937 ms | 1.731 ms | 661.707 μs | 326.883 μs | 161.012 μs | 116.341 μs | — | — | 1.460 ms | 181.792 μs |
| combine! vec | Float32 256^3 | 26.616 ms | 24.004 ms | 18.893 ms | 17.671 ms | 14.107 ms | 13.675 ms | 13.753 ms | 14.045 ms | — | — | 4.150 ms | 1.021 ms |
| combine! vec | Float32 512^3 | — | — | — | — | 116.301 ms | 109.037 ms | 110.323 ms | 110.872 ms | — | — | 19.880 ms | — |
| combine! vec | Float32 64^3 | 129.345 μs | 71.185 μs | 38.072 μs | 19.846 μs | 65.521 μs | 34.150 μs | 20.050 μs | 14.900 μs | — | — | 1.124 ms | 69.521 μs |
| combine! vec | Float64 128^3 | 6.186 ms | 5.637 ms | 4.316 ms | 4.084 ms | 2.327 ms | 1.818 ms | 1.678 ms | 1.639 ms | — | — | 1.695 ms | 240.713 μs |
| combine! vec | Float64 256^3 | 53.020 ms | 48.164 ms | 37.890 ms | 35.457 ms | 28.317 ms | 26.834 ms | 27.180 ms | 27.758 ms | — | — | 4.922 ms | 1.596 ms |
| combine! vec | Float64 512^3 | — | — | — | — | 219.409 ms | 208.968 ms | 219.121 ms | 225.090 ms | — | — | — | — |
| combine! vec | Float64 64^3 | 269.387 μs | 146.932 μs | 80.411 μs | 45.637 μs | 122.831 μs | 64.461 μs | 35.050 μs | 29.010 μs | — | — | 1.119 ms | 67.550 μs |
| cross! | Float32 128^3 | 3.081 ms | 2.621 ms | 2.296 ms | 2.180 ms | 2.062 ms | 976.570 μs | 497.935 μs | 248.143 μs | 1.223 ms | 3.445 ms | 1.087 ms | 130.132 μs |
| cross! | Float32 256^3 | 28.931 ms | 26.586 ms | 24.325 ms | 23.702 ms | 24.784 ms | 14.720 ms | 12.777 ms | 12.935 ms | — | 14.690 ms | 1.775 ms | 836.808 μs |
| cross! | Float32 512^3 | — | — | — | — | 193.079 ms | 122.123 ms | 111.434 ms | 111.776 ms | — | — | 7.558 ms | — |
| cross! | Float32 64^3 | 262.350 μs | 129.860 μs | 72.659 μs | 39.588 μs | 224.633 μs | 115.252 μs | 58.750 μs | 32.700 μs | 219.582 μs | 1.665 ms | 1.031 ms | 71.050 μs |
| cross! | Float64 128^3 | 6.532 ms | 6.049 ms | 5.442 ms | 5.440 ms | 3.998 ms | 2.402 ms | 1.666 ms | 1.628 ms | 1.263 ms | 2.603 ms | 1.367 ms | 256.042 μs |
| cross! | Float64 256^3 | 58.605 ms | 53.033 ms | 49.389 ms | 46.968 ms | 43.486 ms | 29.667 ms | 27.562 ms | 27.819 ms | — | 15.625 ms | 2.733 ms | 1.605 ms |
| cross! | Float64 512^3 | — | — | — | — | 274.550 ms | 215.486 ms | 218.819 ms | 223.753 ms | — | — | — | — |
| cross! | Float64 64^3 | 373.469 μs | 187.020 μs | 101.539 μs | 53.528 μs | 225.472 μs | 115.821 μs | 59.070 μs | 38.171 μs | 216.592 μs | 1.846 ms | 1.103 ms | 65.411 μs |
| det! tensor | Float32 128^3 | 3.660 ms | 2.587 ms | 2.160 ms | 1.966 ms | 2.275 ms | 1.120 ms | 548.206 μs | 282.203 μs | — | — | 1.218 ms | 173.692 μs |
| det! tensor | Float32 256^3 | 36.447 ms | 25.949 ms | 23.192 ms | 21.245 ms | 31.317 ms | 18.437 ms | 12.420 ms | 12.386 ms | — | — | 2.219 ms | 948.070 μs |
| det! tensor | Float32 512^3 | — | — | — | — | 221.325 ms | 126.026 ms | 105.069 ms | 103.382 ms | — | — | 9.408 ms | — |
| det! tensor | Float32 64^3 | 361.565 μs | 186.619 μs | 83.056 μs | 46.689 μs | 255.672 μs | 128.272 μs | 66.581 μs | 37.141 μs | — | — | 966.709 μs | 65.701 μs |
| det! tensor | Float64 128^3 | 6.753 ms | 5.973 ms | 4.837 ms | 4.566 ms | 4.100 ms | 2.523 ms | 1.747 ms | 1.788 ms | — | — | 1.460 ms | 269.943 μs |
| det! tensor | Float64 256^3 | 54.980 ms | 52.857 ms | 43.163 ms | 39.883 ms | 41.688 ms | 29.496 ms | 26.022 ms | 25.976 ms | — | — | 2.941 ms | 1.857 ms |
| det! tensor | Float64 512^3 | — | — | — | — | 384.328 ms | 267.140 ms | 217.907 ms | 218.856 ms | — | — | — | — |
| det! tensor | Float64 64^3 | 363.147 μs | 220.005 μs | 110.514 μs | 60.662 μs | 254.892 μs | 150.272 μs | 76.740 μs | 43.210 μs | — | — | 1.071 ms | 73.711 μs |
| dot! vec.vec | Float32 128^3 | 2.899 ms | 1.731 ms | 1.349 ms | 1.223 ms | 2.494 ms | 1.251 ms | 628.226 μs | 318.793 μs | 538.855 μs | 2.430 ms | 1.239 ms | 113.611 μs |
| dot! vec.vec | Float32 256^3 | 24.982 ms | 18.857 ms | 15.827 ms | 15.018 ms | 22.338 ms | 11.911 ms | 8.390 ms | 8.429 ms | — | 9.651 ms | 2.506 ms | 686.607 μs |
| dot! vec.vec | Float32 512^3 | — | — | — | — | 171.256 ms | 89.154 ms | 76.438 ms | 75.532 ms | — | — | 11.342 ms | — |
| dot! vec.vec | Float32 64^3 | 336.093 μs | 201.695 μs | 106.726 μs | 61.308 μs | 311.953 μs | 159.522 μs | 82.871 μs | 44.841 μs | 112.901 μs | 1.663 ms | 1.107 ms | 77.071 μs |
| dot! vec.vec | Float64 128^3 | 4.596 ms | 3.946 ms | 3.317 ms | 3.108 ms | 3.491 ms | 1.945 ms | 1.012 ms | 641.626 μs | 618.906 μs | 2.505 ms | 1.223 ms | 193.012 μs |
| dot! vec.vec | Float64 256^3 | 44.072 ms | 36.289 ms | 30.450 ms | 28.480 ms | 31.612 ms | 19.788 ms | 18.239 ms | 18.286 ms | — | 9.784 ms | 2.819 ms | 1.233 ms |
| dot! vec.vec | Float64 512^3 | — | — | — | — | 218.536 ms | 151.439 ms | 148.687 ms | 150.958 ms | — | — | — | — |
| dot! vec.vec | Float64 64^3 | 342.485 μs | 207.767 μs | 108.330 μs | 66.523 μs | 318.454 μs | 163.551 μs | 82.531 μs | 44.970 μs | 127.611 μs | 1.656 ms | 1.019 ms | 62.500 μs |
| map!(+) vec | Float32 128^3 | — | — | — | — | 1.713 ms | 816.879 μs | 418.654 μs | 205.732 μs | — | — | — | 120.861 μs |
| map!(+) vec | Float32 256^3 | — | — | — | — | 22.855 ms | 14.255 ms | 12.810 ms | 12.977 ms | — | — | — | 833.159 μs |
| map!(+) vec | Float32 512^3 | — | — | — | — | 181.816 ms | 119.823 ms | 111.163 ms | 111.900 ms | — | — | — | — |
| map!(+) vec | Float32 64^3 | — | — | — | — | 174.701 μs | 93.901 μs | 48.661 μs | 27.020 μs | — | — | — | 58.611 μs |
| map!(+) vec | Float64 128^3 | — | — | — | — | 4.002 ms | 2.272 ms | 1.643 ms | 1.636 ms | — | — | — | 262.272 μs |
| map!(+) vec | Float64 256^3 | — | — | — | — | 41.042 ms | 29.032 ms | 27.534 ms | 27.805 ms | — | — | — | 1.609 ms |
| map!(+) vec | Float64 512^3 | — | — | — | — | 264.211 ms | 214.834 ms | 219.548 ms | 225.799 ms | — | — | — | — |
| map!(+) vec | Float64 64^3 | — | — | — | — | 175.272 μs | 94.711 μs | 48.340 μs | 32.190 μs | — | — | — | 62.001 μs |
| map!(det) tensor | Float32 128^3 | — | — | — | — | 2.248 ms | 1.105 ms | 545.225 μs | 281.293 μs | — | — | — | 179.361 μs |
| map!(det) tensor | Float32 256^3 | — | — | — | — | 31.095 ms | 18.382 ms | 12.416 ms | 12.434 ms | — | — | — | 1.001 ms |
| map!(det) tensor | Float32 512^3 | — | — | — | — | 225.563 ms | 125.990 ms | 104.669 ms | 103.595 ms | — | — | — | — |
| map!(det) tensor | Float32 64^3 | — | — | — | — | 251.223 μs | 127.601 μs | 65.401 μs | 37.030 μs | — | — | — | 73.781 μs |
| map!(det) tensor | Float64 128^3 | — | — | — | — | 4.069 ms | 2.470 ms | 1.731 ms | 1.791 ms | — | — | — | 269.443 μs |
| map!(det) tensor | Float64 256^3 | — | — | — | — | 41.647 ms | 29.250 ms | 25.893 ms | 26.026 ms | — | — | — | 1.859 ms |
| map!(det) tensor | Float64 512^3 | — | — | — | — | 374.914 ms | 255.279 ms | 214.083 ms | 215.775 ms | — | — | — | — |
| map!(det) tensor | Float64 64^3 | — | — | — | — | 252.023 μs | 129.991 μs | 67.211 μs | 42.170 μs | — | — | — | 70.021 μs |
| mul! tensor.vec | Float32 128^3 | 5.241 ms | 4.508 ms | 4.097 ms | 3.891 ms | 3.383 ms | 1.909 ms | 1.013 ms | 889.149 μs | 1.525 ms | 4.295 ms | 1.202 ms | 204.382 μs |
| mul! tensor.vec | Float32 256^3 | 56.838 ms | 41.730 ms | 39.368 ms | 37.470 ms | 33.644 ms | 28.843 ms | 21.403 ms | 21.554 ms | — | 16.892 ms | 2.504 ms | 1.320 ms |
| mul! tensor.vec | Float32 512^3 | — | — | — | — | 335.829 ms | 212.664 ms | 178.058 ms | 175.897 ms | — | — | 12.936 ms | — |
| mul! tensor.vec | Float32 64^3 | 628.537 μs | 242.475 μs | 121.446 μs | 68.588 μs | 371.164 μs | 211.752 μs | 107.151 μs | 57.910 μs | 255.702 μs | 1.882 ms | 1.051 ms | 75.681 μs |
| mul! tensor.vec | Float64 128^3 | 11.484 ms | 10.231 ms | 9.209 ms | 9.025 ms | 7.002 ms | 5.379 ms | 4.558 ms | 4.477 ms | 1.748 ms | 4.757 ms | 1.469 ms | 378.413 μs |
| mul! tensor.vec | Float64 256^3 | 90.503 ms | 85.167 ms | 77.262 ms | 74.028 ms | 58.851 ms | 52.257 ms | 44.277 ms | 44.949 ms | — | 17.818 ms | 3.896 ms | 2.573 ms |
| mul! tensor.vec | Float64 512^3 | — | — | — | — | 550.660 ms | 391.627 ms | 353.622 ms | 362.319 ms | — | — | — | — |
| mul! tensor.vec | Float64 64^3 | 695.993 μs | 473.800 μs | 359.566 μs | 211.291 μs | 377.714 μs | 215.302 μs | 109.261 μs | 59.871 μs | 280.183 μs | 1.951 ms | 1.082 ms | 75.400 μs |
| norm! vec | Float32 128^3 | 746.619 μs | 599.150 μs | 478.282 μs | 359.445 μs | 227.682 μs | 116.721 μs | 63.591 μs | 53.151 μs | 411.304 μs | 2.110 ms | 1.077 ms | 85.811 μs |
| norm! vec | Float32 256^3 | 10.798 ms | 10.148 ms | 8.212 ms | 7.831 ms | 5.421 ms | 4.406 ms | 4.306 ms | 4.425 ms | — | 7.304 ms | 2.143 ms | 392.724 μs |
| norm! vec | Float32 512^3 | — | — | — | — | 53.242 ms | 45.907 ms | 46.260 ms | 46.700 ms | — | — | 7.958 ms | — |
| norm! vec | Float32 64^3 | 54.472 μs | 38.606 μs | 20.836 μs | 16.505 μs | 31.280 μs | 19.980 μs | 12.790 μs | 11.060 μs | 100.251 μs | 1.526 ms | 1.029 ms | 74.951 μs |
| norm! vec | Float64 128^3 | 2.313 ms | 2.021 ms | 1.631 ms | 1.458 ms | 480.455 μs | 252.163 μs | 132.282 μs | 104.961 μs | 463.344 μs | 1.434 ms | 1.433 ms | 168.932 μs |
| norm! vec | Float64 256^3 | 22.327 ms | 20.362 ms | 16.905 ms | 15.982 ms | 12.114 ms | 10.537 ms | 10.595 ms | 10.942 ms | — | 9.850 ms | 3.294 ms | 730.948 μs |
| norm! vec | Float64 512^3 | — | — | — | — | 97.256 ms | 90.112 ms | 91.861 ms | 93.843 ms | — | — | — | — |
| norm! vec | Float64 64^3 | 160.911 μs | 91.195 μs | 50.848 μs | 32.368 μs | 56.101 μs | 34.950 μs | 21.790 μs | 16.120 μs | 101.231 μs | 1.681 ms | 1.117 ms | 65.421 μs |
| tr! tensor | Float32 128^3 | 714.866 μs | 548.546 μs | 465.762 μs | 349.269 μs | 226.672 μs | 113.011 μs | 60.901 μs | 50.980 μs | — | — | 1.021 ms | 85.861 μs |
| tr! tensor | Float32 256^3 | 10.668 ms | 9.839 ms | 8.090 ms | 7.701 ms | 5.271 ms | 4.530 ms | 4.481 ms | 4.683 ms | — | — | 1.859 ms | 393.544 μs |
| tr! tensor | Float32 512^3 | — | — | — | — | 50.297 ms | 46.243 ms | 46.448 ms | 46.832 ms | — | — | 8.577 ms | — |
| tr! tensor | Float32 64^3 | 53.777 μs | 34.817 μs | 16.681 μs | 14.213 μs | 27.580 μs | 18.601 μs | 11.200 μs | 9.250 μs | — | — | 1.108 ms | 88.551 μs |
| tr! tensor | Float64 128^3 | 2.278 ms | 1.979 ms | 1.580 ms | 1.405 ms | 457.325 μs | 234.133 μs | 122.401 μs | 99.661 μs | — | — | 1.153 ms | 117.941 μs |
| tr! tensor | Float64 256^3 | 21.191 ms | 19.901 ms | 16.409 ms | 15.480 ms | 11.893 ms | 10.867 ms | 10.965 ms | 11.316 ms | — | — | 2.035 ms | 734.787 μs |
| tr! tensor | Float64 512^3 | — | — | — | — | 95.501 ms | 92.729 ms | 93.214 ms | 95.679 ms | — | — | — | — |
| tr! tensor | Float64 64^3 | 107.137 μs | 64.410 μs | 34.513 μs | 22.760 μs | 53.051 μs | 31.510 μs | 18.930 μs | 14.850 μs | — | — | 1.004 ms | 58.310 μs |

## operators

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.644 ms | 2.884 ms | 1.570 ms | 1.284 ms | 3.219 ms | 1.685 ms | 830.868 μs | 427.065 μs | 697.807 μs | 2.544 ms | 1.114 ms | 86.111 μs |
| curl! vec->vec | Float32 256^3 | 47.565 ms | 23.207 ms | 18.167 ms | 17.606 ms | 25.621 ms | 13.981 ms | 8.920 ms | 8.988 ms | — | 10.865 ms | 1.562 ms | 594.926 μs |
| curl! vec->vec | Float32 512^3 | — | — | — | — | 232.927 ms | 113.258 ms | 82.809 ms | 83.581 ms | — | — | 6.384 ms | — |
| curl! vec->vec | Float32 64^3 | 715.869 μs | 361.298 μs | 185.059 μs | 97.663 μs | 414.814 μs | 218.823 μs | 111.411 μs | 59.070 μs | 182.902 μs | 1.646 ms | 1.026 ms | 58.860 μs |
| curl! vec->vec | Float64 128^3 | 5.732 ms | 4.247 ms | 3.988 ms | 3.859 ms | 3.785 ms | 1.877 ms | 955.190 μs | 543.445 μs | 824.588 μs | 3.153 ms | 1.535 ms | 196.171 μs |
| curl! vec->vec | Float64 256^3 | 48.543 ms | 38.387 ms | 36.437 ms | 35.207 ms | 33.898 ms | 20.691 ms | 19.738 ms | 20.159 ms | — | 13.647 ms | 3.147 ms | 1.120 ms |
| curl! vec->vec | Float64 512^3 | — | — | — | — | 252.917 ms | 169.238 ms | 164.194 ms | 167.301 ms | — | — | — | — |
| curl! vec->vec | Float64 64^3 | 685.445 μs | 351.104 μs | 180.555 μs | 96.016 μs | 473.165 μs | 231.782 μs | 117.341 μs | 65.771 μs | 186.242 μs | 1.786 ms | 1.155 ms | 75.831 μs |
| divergence! vec->scalar | Float32 128^3 | 3.583 ms | 1.379 ms | 726.007 μs | 414.664 μs | 3.355 ms | 1.113 ms | 562.015 μs | 288.112 μs | 326.353 μs | 1.957 ms | 1.144 ms | 86.450 μs |
| divergence! vec->scalar | Float32 256^3 | 29.383 ms | 11.815 ms | 9.639 ms | 9.114 ms | 26.876 ms | 8.992 ms | 4.587 ms | 4.356 ms | — | 5.523 ms | 1.734 ms | 399.064 μs |
| divergence! vec->scalar | Float32 512^3 | — | — | — | — | 211.569 ms | 69.716 ms | 46.493 ms | 46.374 ms | — | — | 6.985 ms | — |
| divergence! vec->scalar | Float32 64^3 | 427.482 μs | 176.505 μs | 93.067 μs | 51.431 μs | 433.314 μs | 151.911 μs | 78.840 μs | 42.370 μs | 93.900 μs | 1.537 ms | 971.404 μs | 63.800 μs |
| divergence! vec->scalar | Float64 128^3 | 3.927 ms | 2.101 ms | 1.724 ms | 1.552 ms | 3.347 ms | 1.053 ms | 533.425 μs | 277.332 μs | 407.644 μs | 2.306 ms | 1.190 ms | 136.231 μs |
| divergence! vec->scalar | Float64 256^3 | 32.045 ms | 22.048 ms | 17.831 ms | 16.405 ms | 27.431 ms | 11.240 ms | 10.691 ms | 10.722 ms | — | 7.090 ms | 2.578 ms | 747.888 μs |
| divergence! vec->scalar | Float64 512^3 | — | — | — | — | 211.567 ms | 95.299 ms | 93.616 ms | 93.889 ms | — | — | — | — |
| divergence! vec->scalar | Float64 64^3 | 444.337 μs | 163.080 μs | 87.120 μs | 53.950 μs | 446.915 μs | 144.731 μs | 74.001 μs | 41.761 μs | 103.111 μs | 344.869 μs | 982.625 μs | 67.930 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 4.411 ms | 1.797 ms | 988.567 μs | 683.645 μs | 4.939 ms | 2.045 ms | 1.036 ms | 523.085 μs | — | — | 1.230 ms | 92.731 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 36.347 ms | 14.813 ms | 12.158 ms | 11.437 ms | 39.723 ms | 16.222 ms | 8.163 ms | 4.516 ms | — | — | 2.109 ms | 409.174 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | — | — | — | — | 316.060 ms | 128.283 ms | 64.632 ms | 46.830 ms | — | — | 7.652 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 539.303 μs | 233.316 μs | 134.678 μs | 71.987 μs | 634.486 μs | 272.213 μs | 139.651 μs | 74.791 μs | — | — | 1.103 ms | 70.081 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 4.877 ms | 2.753 ms | 2.260 ms | 2.157 ms | 4.921 ms | 1.953 ms | 995.920 μs | 506.585 μs | — | — | 1.365 ms | 181.782 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 39.931 ms | 26.505 ms | 21.953 ms | 20.596 ms | 40.048 ms | 15.880 ms | 10.719 ms | 10.910 ms | — | — | 2.922 ms | 740.417 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | — | — | — | — | 311.648 ms | 123.205 ms | 94.046 ms | 94.674 ms | — | — | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 533.393 μs | 216.600 μs | 115.672 μs | 70.444 μs | 647.327 μs | 260.862 μs | 132.951 μs | 72.001 μs | — | — | 1.163 ms | 79.540 μs |
| gradient! scalar->vec | Float32 128^3 | 3.262 ms | 1.702 ms | 880.984 μs | 532.987 μs | 1.939 ms | 975.710 μs | 490.115 μs | 253.523 μs | 560.525 μs | 2.377 ms | 1.076 ms | 77.700 μs |
| gradient! scalar->vec | Float32 256^3 | 26.249 ms | 15.053 ms | 13.785 ms | 13.763 ms | 15.984 ms | 7.879 ms | 5.992 ms | 5.971 ms | — | 7.929 ms | 1.569 ms | 440.714 μs |
| gradient! scalar->vec | Float32 512^3 | — | — | — | — | 124.350 ms | 65.785 ms | 63.948 ms | 63.985 ms | — | — | 4.394 ms | — |
| gradient! scalar->vec | Float32 64^3 | 415.585 μs | 221.863 μs | 107.430 μs | 58.414 μs | 248.022 μs | 126.331 μs | 64.701 μs | 35.200 μs | 133.261 μs | 1.681 ms | 1.016 ms | 62.801 μs |
| gradient! scalar->vec | Float64 128^3 | 3.461 ms | 2.907 ms | 2.635 ms | 2.547 ms | 2.075 ms | 1.001 ms | 497.915 μs | 258.463 μs | 605.225 μs | 2.717 ms | 1.313 ms | 168.321 μs |
| gradient! scalar->vec | Float64 256^3 | 32.069 ms | 29.672 ms | 28.081 ms | 27.512 ms | 20.323 ms | 15.199 ms | 14.464 ms | 14.751 ms | — | 10.338 ms | 2.498 ms | 807.958 μs |
| gradient! scalar->vec | Float64 512^3 | — | — | — | — | 161.266 ms | 129.180 ms | 126.444 ms | 129.610 ms | — | — | — | — |
| gradient! scalar->vec | Float64 64^3 | 368.859 μs | 192.400 μs | 94.043 μs | 56.623 μs | 256.483 μs | 124.152 μs | 63.860 μs | 35.490 μs | 153.172 μs | 1.872 ms | 1.022 ms | 66.161 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.405 ms | 2.303 ms | 1.399 ms | 1.289 ms | 3.379 ms | 1.692 ms | 848.018 μs | 430.344 μs | 1.480 ms | 4.174 ms | 1.196 ms | 92.111 μs |
| helmholtz! vec->vec | Float32 256^3 | 36.655 ms | 19.651 ms | 18.114 ms | 17.670 ms | 26.929 ms | 14.108 ms | 8.924 ms | 8.973 ms | — | 16.637 ms | 1.739 ms | 603.926 μs |
| helmholtz! vec->vec | Float32 512^3 | — | — | — | — | 239.862 ms | 117.793 ms | 82.735 ms | 83.600 ms | — | — | 6.606 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 558.786 μs | 286.971 μs | 150.825 μs | 78.160 μs | 445.184 μs | 229.192 μs | 116.382 μs | 61.321 μs | 286.333 μs | 1.935 ms | 1.057 ms | 65.710 μs |
| helmholtz! vec->vec | Float64 128^3 | 5.186 ms | 4.220 ms | 3.854 ms | 3.823 ms | 3.931 ms | 1.974 ms | 1.018 ms | 545.185 μs | 1.802 ms | 5.921 ms | 1.598 ms | 244.452 μs |
| helmholtz! vec->vec | Float64 256^3 | 44.813 ms | 38.769 ms | 36.382 ms | 35.180 ms | 34.760 ms | 20.755 ms | 19.796 ms | 20.114 ms | — | 18.240 ms | 3.879 ms | 1.423 ms |
| helmholtz! vec->vec | Float64 512^3 | — | — | — | — | 261.191 ms | 170.810 ms | 164.582 ms | 168.865 ms | — | — | — | — |
| helmholtz! vec->vec | Float64 64^3 | 593.457 μs | 310.953 μs | 156.789 μs | 86.253 μs | 512.885 μs | 264.373 μs | 131.581 μs | 72.281 μs | 342.613 μs | 2.260 ms | 1.218 ms | 83.631 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 6.146 ms | 3.063 ms | 1.840 ms | 1.618 ms | 6.317 ms | 3.173 ms | 1.586 ms | 800.058 μs | — | — | 1.065 ms | 93.521 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 50.158 ms | 24.608 ms | 20.555 ms | 19.673 ms | 50.283 ms | 25.321 ms | 12.714 ms | 9.143 ms | — | — | 1.706 ms | 603.086 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | — | — | — | — | 403.778 ms | 202.280 ms | 101.287 ms | 82.965 ms | — | — | 7.390 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 779.149 μs | 395.970 μs | 200.974 μs | 106.172 μs | 823.368 μs | 427.135 μs | 215.172 μs | 110.111 μs | — | — | 1.107 ms | 74.441 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 6.666 ms | 4.845 ms | 4.468 ms | 4.407 ms | 6.889 ms | 3.477 ms | 1.746 ms | 888.039 μs | — | — | 1.683 ms | 275.893 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 56.105 ms | 43.079 ms | 40.773 ms | 39.444 ms | 56.042 ms | 27.706 ms | 19.769 ms | 20.007 ms | — | — | 4.462 ms | 1.637 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | — | — | — | — | 435.294 ms | 222.716 ms | 165.129 ms | 167.435 ms | — | — | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 817.503 μs | 417.490 μs | 213.933 μs | 113.394 μs | 913.279 μs | 457.485 μs | 229.323 μs | 122.421 μs | — | — | 964.417 μs | 90.251 μs |
| inverse_laplacian! scalar | Float32 128^3 | — | — | — | — | 3.907 ms | 1.321 ms | 666.757 μs | 341.304 μs | — | — | — | 83.360 μs |
| inverse_laplacian! scalar | Float32 256^3 | — | — | — | — | 31.382 ms | 10.666 ms | 5.330 ms | 2.736 ms | — | — | — | 285.623 μs |
| inverse_laplacian! scalar | Float32 512^3 | — | — | — | — | 250.227 ms | 83.552 ms | 42.058 ms | 27.724 ms | — | — | — | — |
| inverse_laplacian! scalar | Float32 64^3 | — | — | — | — | 497.375 μs | 175.882 μs | 93.111 μs | 52.481 μs | — | — | — | 66.231 μs |
| inverse_laplacian! scalar | Float64 128^3 | — | — | — | — | 4.250 ms | 1.430 ms | 719.817 μs | 368.394 μs | — | — | — | 98.161 μs |
| inverse_laplacian! scalar | Float64 256^3 | — | — | — | — | 34.492 ms | 11.543 ms | 5.844 ms | 5.157 ms | — | — | — | 411.394 μs |
| inverse_laplacian! scalar | Float64 512^3 | — | — | — | — | 273.286 ms | 90.895 ms | 53.633 ms | 55.213 ms | — | — | — | — |
| inverse_laplacian! scalar | Float64 64^3 | — | — | — | — | 540.515 μs | 191.332 μs | 99.842 μs | 56.120 μs | — | — | — | 61.981 μs |
| laplacian! scalar | Float32 128^3 | 2.064 ms | 654.294 μs | 335.668 μs | 174.654 μs | 2.147 ms | 491.865 μs | 249.872 μs | 129.991 μs | 265.103 μs | 1.910 ms | 1.181 ms | 73.811 μs |
| laplacian! scalar | Float32 256^3 | 17.204 ms | 6.266 ms | 5.114 ms | 4.573 ms | 17.058 ms | 3.843 ms | 1.954 ms | 1.292 ms | — | 5.490 ms | 1.688 ms | 246.413 μs |
| laplacian! scalar | Float32 512^3 | — | — | — | — | 136.380 ms | 30.770 ms | 25.938 ms | 26.352 ms | — | — | 5.262 ms | — |
| laplacian! scalar | Float32 64^3 | 253.409 μs | 90.201 μs | 49.778 μs | 29.951 μs | 274.913 μs | 68.341 μs | 36.760 μs | 22.140 μs | 83.431 μs | 1.563 ms | 957.239 μs | 61.041 μs |
| laplacian! scalar | Float64 128^3 | 2.151 ms | 818.689 μs | 625.527 μs | 453.410 μs | 2.208 ms | 527.106 μs | 267.003 μs | 140.931 μs | 278.082 μs | 1.957 ms | 1.174 ms | 76.690 μs |
| laplacian! scalar | Float64 256^3 | 17.670 ms | 12.629 ms | 11.985 ms | 11.511 ms | 17.752 ms | 5.206 ms | 4.972 ms | 5.082 ms | — | 4.740 ms | 1.795 ms | 406.254 μs |
| laplacian! scalar | Float64 512^3 | — | — | — | — | 141.227 ms | 52.887 ms | 53.371 ms | 54.901 ms | — | — | — | — |
| laplacian! scalar | Float64 64^3 | 258.431 μs | 94.484 μs | 52.006 μs | 32.627 μs | 281.353 μs | 73.661 μs | 39.101 μs | 23.730 μs | 84.420 μs | 1.586 ms | 1.058 ms | 59.211 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.568 ms | 6.270 ms | 4.679 ms | 4.632 ms | 9.641 ms | 4.892 ms | 2.444 ms | 1.239 ms | — | — | 1.173 ms | 211.022 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 95.270 ms | 51.396 ms | 45.242 ms | 43.393 ms | 82.075 ms | 43.250 ms | 25.737 ms | 23.865 ms | — | — | 2.615 ms | 1.193 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | — | — | — | — | 670.960 ms | 334.995 ms | 200.734 ms | 200.459 ms | — | — | 14.783 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.541 ms | 759.204 μs | 384.861 μs | 200.176 μs | 1.217 ms | 621.127 μs | 313.183 μs | 158.332 μs | — | — | 1.040 ms | 77.401 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 14.266 ms | 11.445 ms | 10.440 ms | 10.391 ms | 10.809 ms | 5.919 ms | 4.320 ms | 4.136 ms | — | — | 1.627 ms | 354.154 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 116.759 ms | 95.790 ms | 88.096 ms | 86.966 ms | 91.631 ms | 51.717 ms | 49.397 ms | 50.204 ms | — | — | 4.370 ms | 2.280 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | — | — | — | — | 701.378 ms | 429.939 ms | 394.403 ms | 399.651 ms | — | — | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.606 ms | 785.084 μs | 414.935 μs | 219.733 μs | 1.274 ms | 650.017 μs | 326.753 μs | 170.191 μs | — | — | 1.192 ms | 96.961 μs |

## convolution

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.848 ms | 519.172 μs | 460.198 μs | 358.481 μs | 1.154 μs | 1.160 μs | 1.166 μs | 1.164 μs | 296.642 μs | 1.855 ms | 991.293 μs | 94.101 μs |
| assignment_window | Float32 256^3 | 27.534 ms | 4.133 ms | 5.588 ms | 3.470 ms | 2.210 μs | 2.243 μs | 2.241 μs | 2.238 μs | — | 3.952 ms | 1.684 ms | 91.061 μs |
| assignment_window | Float32 512^3 | — | — | — | — | 4.464 μs | 4.483 μs | 4.500 μs | 4.453 μs | — | — | 5.043 ms | — |
| assignment_window | Float32 64^3 | 240.424 μs | 65.194 μs | 44.367 μs | 38.678 μs | 599.102 ns | 599.556 ns | 606.432 ns | 603.039 ns | 138.651 μs | 1.640 ms | 1.027 ms | 96.501 μs |
| assignment_window | Float64 128^3 | 1.901 ms | 1.011 ms | 820.985 μs | 575.925 μs | 1.536 μs | 1.557 μs | 1.550 μs | 1.563 μs | 306.863 μs | 1.901 ms | 1.136 ms | 96.061 μs |
| assignment_window | Float64 256^3 | 41.039 ms | 8.489 ms | 9.793 ms | 6.226 ms | 3.064 μs | 3.083 μs | 3.072 μs | 3.092 μs | — | 4.237 ms | 1.784 ms | 102.991 μs |
| assignment_window | Float64 512^3 | — | — | — | — | 5.966 μs | 5.992 μs | 5.968 μs | 5.968 μs | — | — | — | — |
| assignment_window | Float64 64^3 | 237.586 μs | 68.329 μs | 65.607 μs | 64.938 μs | 814.768 ns | 814.443 ns | 818.226 ns | 820.378 ns | 141.232 μs | 1.542 ms | 1.162 ms | 92.471 μs |
| combine!∘kernel vector | Float32 128^3 | 4.099 ms | 2.240 ms | 1.715 ms | 1.645 ms | 3.185 ms | 1.565 ms | 779.938 μs | 395.094 μs | — | — | 957.518 μs | 133.111 μs |
| combine!∘kernel vector | Float32 256^3 | 37.490 ms | 22.146 ms | 20.259 ms | 19.790 ms | 25.259 ms | 15.471 ms | 10.284 ms | 10.482 ms | — | — | 1.958 ms | 923.989 μs |
| combine!∘kernel vector | Float32 512^3 | — | — | — | — | 242.548 ms | 111.158 ms | 92.683 ms | 106.554 ms | — | — | 8.534 ms | — |
| combine!∘kernel vector | Float32 64^3 | 494.715 μs | 267.940 μs | 134.409 μs | 75.209 μs | 424.924 μs | 210.792 μs | 104.831 μs | 55.361 μs | — | — | 1.101 ms | 79.410 μs |
| combine!∘kernel vector | Float64 128^3 | 5.648 ms | 4.900 ms | 4.435 ms | 4.427 ms | 3.760 ms | 2.087 ms | 1.132 ms | 850.729 μs | — | — | 1.469 ms | 284.333 μs |
| combine!∘kernel vector | Float64 256^3 | 50.199 ms | 44.417 ms | 40.732 ms | 40.012 ms | 34.247 ms | 23.449 ms | 22.397 ms | 22.662 ms | — | — | 3.008 ms | 1.776 ms |
| combine!∘kernel vector | Float64 512^3 | — | — | — | — | 263.179 ms | 188.918 ms | 184.414 ms | 186.624 ms | — | — | — | — |
| combine!∘kernel vector | Float64 64^3 | 516.288 μs | 283.545 μs | 142.485 μs | 81.472 μs | 383.444 μs | 224.782 μs | 115.171 μs | 63.591 μs | — | — | 1.001 ms | 85.421 μs |
| convolve! scalar | Float32 128^3 | 1.622 ms | 314.111 μs | 205.492 μs | 87.696 μs | 919.219 μs | 103.751 μs | 53.931 μs | 37.551 μs | 220.032 μs | 1.755 ms | 877.910 μs | 65.041 μs |
| convolve! scalar | Float32 256^3 | 13.663 ms | 8.198 ms | 7.751 ms | 7.123 ms | 7.601 ms | 2.931 ms | 2.790 ms | 2.928 ms | — | 3.659 ms | 1.656 ms | 306.184 μs |
| convolve! scalar | Float32 512^3 | — | — | — | — | 61.748 ms | 36.987 ms | 36.334 ms | 36.776 ms | — | — | 4.192 ms | — |
| convolve! scalar | Float32 64^3 | 202.015 μs | 26.689 μs | 14.629 μs | 11.683 μs | 116.212 μs | 16.320 μs | 9.710 μs | 8.080 μs | 78.951 μs | 1.480 ms | 1.035 ms | 51.431 μs |
| convolve! scalar | Float64 128^3 | 1.847 ms | 1.390 ms | 1.185 ms | 1.117 ms | 1.017 ms | 171.161 μs | 91.331 μs | 75.671 μs | 302.553 μs | 1.784 ms | 1.135 ms | 82.181 μs |
| convolve! scalar | Float64 256^3 | 19.136 ms | 16.911 ms | 16.014 ms | 15.178 ms | 10.764 ms | 8.147 ms | 7.902 ms | 8.134 ms | — | 4.442 ms | 2.019 ms | 567.296 μs |
| convolve! scalar | Float64 512^3 | — | — | — | — | 90.360 ms | 73.367 ms | 73.753 ms | 75.483 ms | — | — | — | — |
| convolve! scalar | Float64 64^3 | 181.121 μs | 55.189 μs | 26.100 μs | 18.116 μs | 126.951 μs | 25.120 μs | 14.250 μs | 10.830 μs | 78.591 μs | 1.618 ms | 951.395 μs | 54.231 μs |
| convolve! vector | Float32 128^3 | 2.765 ms | 1.925 ms | 1.659 ms | 1.593 ms | 2.113 ms | 1.111 ms | 553.196 μs | 282.873 μs | 731.727 μs | 2.557 ms | 921.484 μs | 109.431 μs |
| convolve! vector | Float32 256^3 | 26.736 ms | 21.677 ms | 20.002 ms | 19.668 ms | 19.892 ms | 11.382 ms | 10.257 ms | 10.372 ms | — | 10.821 ms | 1.185 ms | 686.257 μs |
| convolve! vector | Float32 512^3 | — | — | — | — | 177.268 ms | 94.705 ms | 92.274 ms | 92.785 ms | — | — | 6.065 ms | — |
| convolve! vector | Float32 64^3 | 318.386 μs | 178.979 μs | 90.308 μs | 49.964 μs | 268.903 μs | 147.071 μs | 74.480 μs | 40.821 μs | 161.751 μs | 1.595 ms | 1.094 ms | 61.751 μs |
| convolve! vector | Float64 128^3 | 5.261 ms | 4.843 ms | 4.388 ms | 4.243 ms | 2.724 ms | 1.585 ms | 918.689 μs | 817.399 μs | 792.657 μs | 2.910 ms | 1.329 ms | 239.743 μs |
| convolve! vector | Float64 256^3 | 46.440 ms | 43.366 ms | 40.450 ms | 39.756 ms | 30.810 ms | 23.152 ms | 22.368 ms | 22.757 ms | — | 12.297 ms | 2.365 ms | 1.293 ms |
| convolve! vector | Float64 512^3 | — | — | — | — | 227.285 ms | 187.315 ms | 184.325 ms | 186.461 ms | — | — | — | — |
| convolve! vector | Float64 64^3 | 284.305 μs | 169.910 μs | 89.571 μs | 54.907 μs | 221.233 μs | 133.061 μs | 72.051 μs | 41.270 μs | 167.451 μs | 1.655 ms | 1.102 ms | 67.601 μs |
| convolve! vector ∘ radial    | Float32 128^3 | — | — | — | — | 2.488 ms | 1.265 ms | 623.387 μs | 320.673 μs | — | — | — | 131.431 μs |
| convolve! vector ∘ radial    | Float32 256^3 | — | — | — | — | 19.853 ms | 10.111 ms | 8.595 ms | 8.746 ms | — | — | — | 679.007 μs |
| convolve! vector ∘ radial    | Float32 512^3 | — | — | — | — | 159.841 ms | 85.777 ms | 81.209 ms | 82.288 ms | — | — | — | — |
| convolve! vector ∘ radial    | Float32 64^3 | — | — | — | — | 316.813 μs | 160.112 μs | 81.501 μs | 44.430 μs | — | — | — | 73.530 μs |
| convolve! vector ∘ radial    | Float64 128^3 | — | — | — | — | 2.910 ms | 1.463 ms | 733.558 μs | 408.044 μs | — | — | — | 209.982 μs |
| convolve! vector ∘ radial    | Float64 256^3 | — | — | — | — | 24.370 ms | 18.946 ms | 19.190 ms | 19.531 ms | — | — | — | 1.114 ms |
| convolve! vector ∘ radial    | Float64 512^3 | — | — | — | — | 196.847 ms | 159.017 ms | 162.237 ms | 164.761 ms | — | — | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | — | — | — | — | 354.584 μs | 176.962 μs | 92.201 μs | 49.690 μs | — | — | — | 70.591 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | — | — | — | — | 2.111 ms | 1.108 ms | 558.716 μs | 283.733 μs | — | — | — | 114.351 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | — | — | — | — | 19.901 ms | 11.154 ms | 10.197 ms | 10.335 ms | — | — | — | 688.207 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | — | — | — | — | 176.633 ms | 94.525 ms | 91.964 ms | 92.703 ms | — | — | — | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | — | — | — | — | 271.453 μs | 147.772 μs | 74.391 μs | 40.481 μs | — | — | — | 63.840 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | — | — | — | — | 2.726 ms | 1.613 ms | 938.769 μs | 822.789 μs | — | — | — | 221.162 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | — | — | — | — | 30.592 ms | 22.814 ms | 22.348 ms | 22.628 ms | — | — | — | 1.288 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | — | — | — | — | 227.343 ms | 185.852 ms | 183.429 ms | 185.672 ms | — | — | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | — | — | — | — | 220.532 μs | 134.161 μs | 73.391 μs | 41.081 μs | — | — | — | 70.080 μs |
| convolve! vector ∘ separable | Float32 128^3 | — | — | — | — | 4.655 ms | 2.340 ms | 1.168 ms | 590.186 μs | — | — | — | 130.291 μs |
| convolve! vector ∘ separable | Float32 256^3 | — | — | — | — | 37.334 ms | 18.853 ms | 9.455 ms | 9.039 ms | — | — | — | 686.917 μs |
| convolve! vector ∘ separable | Float32 512^3 | — | — | — | — | 298.064 ms | 148.988 ms | 82.455 ms | 82.655 ms | — | — | — | — |
| convolve! vector ∘ separable | Float32 64^3 | — | — | — | — | 590.876 μs | 298.293 μs | 150.732 μs | 78.101 μs | — | — | — | 59.600 μs |
| convolve! vector ∘ separable | Float64 128^3 | — | — | — | — | 3.951 ms | 1.984 ms | 1.003 ms | 514.756 μs | — | — | — | 274.343 μs |
| convolve! vector ∘ separable | Float64 256^3 | — | — | — | — | 32.590 ms | 19.639 ms | 19.386 ms | 19.698 ms | — | — | — | 1.676 ms |
| convolve! vector ∘ separable | Float64 512^3 | — | — | — | — | 257.446 ms | 164.149 ms | 163.294 ms | 168.594 ms | — | — | — | — |
| convolve! vector ∘ separable | Float64 64^3 | — | — | — | — | 495.175 μs | 249.763 μs | 126.281 μs | 66.751 μs | — | — | — | 77.240 μs |
| convolve! vector ∘ stored    | Float32 128^3 | — | — | — | — | 2.108 ms | 1.108 ms | 556.305 μs | 283.753 μs | — | — | — | 111.701 μs |
| convolve! vector ∘ stored    | Float32 256^3 | — | — | — | — | 19.828 ms | 11.293 ms | 10.244 ms | 10.354 ms | — | — | — | 681.486 μs |
| convolve! vector ∘ stored    | Float32 512^3 | — | — | — | — | 177.364 ms | 94.898 ms | 92.193 ms | 92.992 ms | — | — | — | — |
| convolve! vector ∘ stored    | Float32 64^3 | — | — | — | — | 269.052 μs | 147.562 μs | 74.491 μs | 40.751 μs | — | — | — | 65.791 μs |
| convolve! vector ∘ stored    | Float64 128^3 | — | — | — | — | 2.739 ms | 1.596 ms | 936.819 μs | 806.938 μs | — | — | — | 226.342 μs |
| convolve! vector ∘ stored    | Float64 256^3 | — | — | — | — | 30.847 ms | 23.057 ms | 22.372 ms | 22.706 ms | — | — | — | 1.286 ms |
| convolve! vector ∘ stored    | Float64 512^3 | — | — | — | — | 225.993 ms | 187.393 ms | 183.794 ms | 186.708 ms | — | — | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | — | — | — | — | 221.482 μs | 133.072 μs | 71.561 μs | 41.591 μs | — | — | — | 68.701 μs |
| exponential_convolve! scalar | Float32 128^3 | 5.737 ms | 2.434 ms | 1.659 ms | 900.167 μs | 5.050 ms | 2.118 ms | 1.066 ms | 539.656 μs | — | — | 1.058 ms | 73.841 μs |
| exponential_convolve! scalar | Float32 256^3 | 34.376 ms | 13.310 ms | 7.294 ms | 5.716 ms | 39.743 ms | 16.723 ms | 8.412 ms | 4.290 ms | — | — | 1.651 ms | 253.413 μs |
| exponential_convolve! scalar | Float32 512^3 | — | — | — | — | 315.569 ms | 131.634 ms | 66.363 ms | 35.217 ms | — | — | 5.951 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 2.197 ms | 1.065 ms | 569.902 μs | 299.039 μs | 642.546 μs | 280.563 μs | 146.911 μs | 78.321 μs | — | — | 999.111 μs | 63.211 μs |
| exponential_convolve! scalar | Float64 128^3 | 8.249 ms | 3.745 ms | 2.332 ms | 1.452 ms | 5.540 ms | 2.413 ms | 1.214 ms | 607.556 μs | — | — | 1.328 ms | 122.261 μs |
| exponential_convolve! scalar | Float64 256^3 | 55.341 ms | 24.571 ms | 14.316 ms | 11.623 ms | 44.045 ms | 18.840 ms | 9.541 ms | 5.264 ms | — | — | 2.622 ms | 629.547 μs |
| exponential_convolve! scalar | Float64 512^3 | — | — | — | — | 350.908 ms | 149.522 ms | 75.035 ms | 59.005 ms | — | — | — | — |
| exponential_convolve! scalar | Float64 64^3 | 728.857 μs | 327.894 μs | 171.385 μs | 96.734 μs | 698.037 μs | 309.504 μs | 157.592 μs | 84.460 μs | — | — | 986.434 μs | 57.921 μs |
| exponential_convolve! vector | Float32 128^3 | 19.222 ms | 9.091 ms | 5.798 ms | 3.138 ms | 16.583 ms | 7.675 ms | 3.837 ms | 1.941 ms | — | — | 1.208 ms | 170.112 μs |
| exponential_convolve! vector | Float32 256^3 | 116.910 ms | 53.126 ms | 28.672 ms | 18.878 ms | 130.579 ms | 60.969 ms | 30.847 ms | 16.352 ms | — | — | 3.202 ms | 700.127 μs |
| exponential_convolve! vector | Float32 512^3 | — | — | — | — | 1.041 s | 478.613 ms | 244.005 ms | 126.182 ms | — | — | 14.658 ms | — |
| exponential_convolve! vector | Float32 64^3 | 6.916 ms | 3.524 ms | 1.824 ms | 944.164 μs | 2.123 ms | 999.130 μs | 500.355 μs | 256.903 μs | — | — | 1.051 ms | 66.960 μs |
| exponential_convolve! vector | Float64 128^3 | 27.270 ms | 12.988 ms | 7.841 ms | 5.008 ms | 18.849 ms | 8.658 ms | 4.347 ms | 2.193 ms | — | — | 1.842 ms | 282.193 μs |
| exponential_convolve! vector | Float64 256^3 | 184.797 ms | 87.239 ms | 47.961 ms | 35.237 ms | 146.700 ms | 68.413 ms | 34.589 ms | 20.857 ms | — | — | 5.713 ms | 1.742 ms |
| exponential_convolve! vector | Float64 512^3 | — | — | — | — | 1.161 s | 544.290 ms | 271.724 ms | 176.298 ms | — | — | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.524 ms | 1.171 ms | 604.600 μs | 321.396 μs | 2.379 ms | 1.101 ms | 552.326 μs | 283.052 μs | — | — | 1.060 ms | 84.250 μs |
| inv separable | Float32 128^3 | — | — | — | — | 697.299 ns | 691.905 ns | 699.007 ns | 696.651 ns | — | — | — | 77.631 μs |
| inv separable | Float32 256^3 | — | — | — | — | 1.407 μs | 1.403 μs | 1.400 μs | 1.404 μs | — | — | — | 80.130 μs |
| inv separable | Float32 512^3 | — | — | — | — | 2.809 μs | 2.741 μs | 2.783 μs | 2.737 μs | — | — | — | — |
| inv separable | Float32 64^3 | — | — | — | — | 366.218 ns | 367.238 ns | 374.541 ns | 367.468 ns | — | — | — | 98.171 μs |
| inv separable | Float64 128^3 | — | — | — | — | 969.000 ns | 977.000 ns | 968.000 ns | 980.000 ns | — | — | — | 76.191 μs |
| inv separable | Float64 256^3 | — | — | — | — | 1.838 μs | 1.889 μs | 1.843 μs | 1.867 μs | — | — | — | 84.771 μs |
| inv separable | Float64 512^3 | — | — | — | — | 3.634 μs | 3.606 μs | 3.601 μs | 3.681 μs | — | — | — | — |
| inv separable | Float64 64^3 | — | — | — | — | 473.270 ns | 470.159 ns | 475.697 ns | 477.800 ns | — | — | — | 83.411 μs |
| materialize_kernel radial | Float32 128^3 | — | — | — | — | 1.132 ms | 350.924 μs | 179.092 μs | 94.581 μs | — | — | — | 83.811 μs |
| materialize_kernel radial | Float32 256^3 | — | — | — | — | 9.014 ms | 2.788 ms | 1.756 ms | 2.023 ms | — | — | — | 227.442 μs |
| materialize_kernel radial | Float32 512^3 | — | — | — | — | 71.114 ms | 22.057 ms | 17.130 ms | 17.148 ms | — | — | — | — |
| materialize_kernel radial | Float32 64^3 | — | — | — | — | 145.792 μs | 48.030 μs | 25.920 μs | 15.770 μs | — | — | — | 64.390 μs |
| materialize_kernel radial | Float64 128^3 | — | — | — | — | 1.175 ms | 382.913 μs | 342.724 μs | 331.364 μs | — | — | — | 94.931 μs |
| materialize_kernel radial | Float64 256^3 | — | — | — | — | 9.412 ms | 4.049 ms | 4.114 ms | 4.209 ms | — | — | — | 249.192 μs |
| materialize_kernel radial | Float64 512^3 | — | — | — | — | 74.145 ms | 94.528 ms | 53.266 ms | 35.685 ms | — | — | — | — |
| materialize_kernel radial | Float64 64^3 | — | — | — | — | 150.991 μs | 48.210 μs | 25.430 μs | 15.930 μs | — | — | — | 71.400 μs |
| materialize_kernel separable | Float32 128^3 | — | — | — | — | 1.536 ms | 446.114 μs | 226.943 μs | 117.111 μs | — | — | — | 87.440 μs |
| materialize_kernel separable | Float32 256^3 | — | — | — | — | 12.236 ms | 3.520 ms | 1.807 ms | 2.042 ms | — | — | — | 236.202 μs |
| materialize_kernel separable | Float32 512^3 | — | — | — | — | 96.592 ms | 28.052 ms | 18.492 ms | 18.545 ms | — | — | — | — |
| materialize_kernel separable | Float32 64^3 | — | — | — | — | 196.722 μs | 59.820 μs | 31.770 μs | 18.900 μs | — | — | — | 66.050 μs |
| materialize_kernel separable | Float64 128^3 | — | — | — | — | 1.449 ms | 457.425 μs | 391.524 μs | 370.034 μs | — | — | — | 109.041 μs |
| materialize_kernel separable | Float64 256^3 | — | — | — | — | 11.637 ms | 4.258 ms | 4.281 ms | 4.451 ms | — | — | — | 411.284 μs |
| materialize_kernel separable | Float64 512^3 | — | — | — | — | 91.309 ms | 106.627 ms | 62.507 ms | 46.954 ms | — | — | — | — |
| materialize_kernel separable | Float64 64^3 | — | — | — | — | 186.702 μs | 61.261 μs | 32.130 μs | 19.570 μs | — | — | — | 72.891 μs |
| radial_kernel | Float32 128^3 | — | — | — | — | 3.180 ns | 3.180 ns | 3.180 ns | 3.190 ns | — | — | — | 1.693 μs |
| radial_kernel | Float32 256^3 | — | — | — | — | 3.190 ns | 3.180 ns | 3.190 ns | 3.180 ns | — | — | — | 1.490 μs |
| radial_kernel | Float32 512^3 | — | — | — | — | 3.050 ns | 3.180 ns | 3.190 ns | 3.050 ns | — | — | — | — |
| radial_kernel | Float32 64^3 | — | — | — | — | 3.180 ns | 3.180 ns | 3.180 ns | 3.190 ns | — | — | — | 2.026 μs |
| radial_kernel | Float64 128^3 | — | — | — | — | 3.200 ns | 3.190 ns | 3.180 ns | 3.180 ns | — | — | — | 1.715 μs |
| radial_kernel | Float64 256^3 | — | — | — | — | 3.210 ns | 3.200 ns | 3.180 ns | 3.180 ns | — | — | — | 1.550 μs |
| radial_kernel | Float64 512^3 | — | — | — | — | 3.180 ns | 3.190 ns | 3.180 ns | 3.190 ns | — | — | — | — |
| radial_kernel | Float64 64^3 | — | — | — | — | 3.210 ns | 3.200 ns | 3.190 ns | 3.180 ns | — | — | — | 1.264 μs |
| spectral_band | Float32 128^3 | 4.252 ms | 1.621 ms | 834.592 μs | 441.121 μs | 1.131 ms | 352.154 μs | 179.662 μs | 94.321 μs | 334.154 μs | 2.050 ms | 1.005 ms | 83.641 μs |
| spectral_band | Float32 256^3 | 46.117 ms | 12.797 ms | 10.084 ms | 5.548 ms | 8.927 ms | 2.790 ms | 1.716 ms | 1.918 ms | — | 6.344 ms | 1.755 ms | 225.463 μs |
| spectral_band | Float32 512^3 | — | — | — | — | 70.909 ms | 22.023 ms | 17.176 ms | 17.149 ms | — | — | 7.315 ms | — |
| spectral_band | Float32 64^3 | 540.920 μs | 216.585 μs | 115.386 μs | 63.530 μs | 145.741 μs | 48.221 μs | 25.750 μs | 15.741 μs | 106.071 μs | 1.537 ms | 1.000 ms | 70.611 μs |
| spectral_band | Float64 128^3 | 4.310 ms | 1.590 ms | 966.909 μs | 624.952 μs | 1.176 ms | 382.524 μs | 337.694 μs | 351.534 μs | 361.113 μs | 2.105 ms | 1.221 ms | 88.561 μs |
| spectral_band | Float64 256^3 | 58.860 ms | 12.495 ms | 13.852 ms | 8.086 ms | 9.514 ms | 4.096 ms | 4.147 ms | 4.176 ms | — | 5.611 ms | 2.014 ms | 241.253 μs |
| spectral_band | Float64 512^3 | — | — | — | — | 74.132 ms | 33.665 ms | 53.155 ms | 35.724 ms | — | — | — | — |
| spectral_band | Float64 64^3 | 530.525 μs | 214.887 μs | 113.729 μs | 71.733 μs | 151.022 μs | 48.401 μs | 26.101 μs | 15.810 μs | 110.411 μs | 1.651 ms | 866.015 μs | 68.441 μs |
| spectral_cutoff | Float32 128^3 | 4.270 ms | 1.655 ms | 839.296 μs | 442.373 μs | 1.130 ms | 351.723 μs | 179.561 μs | 95.581 μs | 331.623 μs | 2.046 ms | 1.093 ms | 83.490 μs |
| spectral_cutoff | Float32 256^3 | 45.919 ms | 12.710 ms | 10.131 ms | 5.435 ms | 9.009 ms | 2.771 ms | 1.603 ms | 1.893 ms | — | 5.403 ms | 1.983 ms | 234.033 μs |
| spectral_cutoff | Float32 512^3 | — | — | — | — | 70.957 ms | 22.076 ms | 17.153 ms | 17.675 ms | — | — | 6.140 ms | — |
| spectral_cutoff | Float32 64^3 | 548.228 μs | 217.012 μs | 114.396 μs | 63.484 μs | 145.722 μs | 48.250 μs | 25.510 μs | 15.701 μs | 108.881 μs | 1.625 ms | 1.105 ms | 78.731 μs |
| spectral_cutoff | Float64 128^3 | 4.261 ms | 1.590 ms | 972.055 μs | 631.094 μs | 1.174 ms | 393.904 μs | 284.653 μs | 261.782 μs | 351.793 μs | 2.120 ms | 1.131 ms | 91.311 μs |
| spectral_cutoff | Float64 256^3 | 59.017 ms | 12.879 ms | 13.948 ms | 8.048 ms | 9.520 ms | 4.076 ms | 4.039 ms | 4.164 ms | — | 5.621 ms | 2.006 ms | 246.942 μs |
| spectral_cutoff | Float64 512^3 | — | — | — | — | 73.950 ms | 94.574 ms | 53.417 ms | 35.974 ms | — | — | — | — |
| spectral_cutoff | Float64 64^3 | 534.876 μs | 213.217 μs | 114.093 μs | 69.801 μs | 151.101 μs | 48.870 μs | 25.590 μs | 15.801 μs | 117.711 μs | 1.647 ms | 1.006 ms | 65.511 μs |
| squared_wavenumber_field | Float32 128^3 | 1.881 ms | 489.911 μs | 448.601 μs | 349.437 μs | 1.375 ms | 299.163 μs | 151.742 μs | 79.291 μs | 262.463 μs | 1.824 ms | 961.813 μs | 88.570 μs |
| squared_wavenumber_field | Float32 256^3 | 27.592 ms | 4.127 ms | 5.585 ms | 3.472 ms | 10.934 ms | 2.278 ms | 1.311 ms | 1.923 ms | — | 3.812 ms | 1.541 ms | 219.282 μs |
| squared_wavenumber_field | Float32 512^3 | — | — | — | — | 86.321 ms | 21.054 ms | 18.236 ms | 17.997 ms | — | — | 4.991 ms | — |
| squared_wavenumber_field | Float32 64^3 | 233.436 μs | 63.047 μs | 35.087 μs | 39.058 μs | 176.612 μs | 42.250 μs | 22.980 μs | 14.220 μs | 91.321 μs | 1.517 ms | 954.784 μs | 78.000 μs |
| squared_wavenumber_field | Float64 128^3 | 1.904 ms | 1.001 ms | 818.893 μs | 591.955 μs | 1.419 ms | 393.324 μs | 322.243 μs | 353.173 μs | 264.163 μs | 1.805 ms | 1.079 ms | 88.781 μs |
| squared_wavenumber_field | Float64 256^3 | 41.025 ms | 8.109 ms | 9.821 ms | 6.080 ms | 11.331 ms | 4.759 ms | 4.559 ms | 4.399 ms | — | 4.151 ms | 1.758 ms | 244.473 μs |
| squared_wavenumber_field | Float64 512^3 | — | — | — | — | 89.787 ms | 92.670 ms | 58.954 ms | 44.579 ms | — | — | — | — |
| squared_wavenumber_field | Float64 64^3 | 235.679 μs | 63.357 μs | 67.986 μs | 62.943 μs | 182.172 μs | 42.871 μs | 23.131 μs | 23.160 μs | 88.931 μs | 1.612 ms | 1.059 ms | 74.320 μs |
| translation_kernel | Float32 128^3 | 1.839 ms | 787.619 μs | 481.587 μs | 331.665 μs | 1.406 μs | 1.414 μs | 1.408 μs | 1.413 μs | — | — | 1.218 ms | 75.451 μs |
| translation_kernel | Float32 256^3 | 27.554 ms | 6.188 ms | 6.949 ms | 4.066 ms | 2.718 μs | 2.736 μs | 2.740 μs | 2.722 μs | — | — | 1.653 ms | 86.221 μs |
| translation_kernel | Float32 512^3 | — | — | — | — | 5.314 μs | 5.329 μs | 5.305 μs | 5.302 μs | — | — | 5.084 ms | — |
| translation_kernel | Float32 64^3 | 232.583 μs | 105.855 μs | 58.738 μs | 40.614 μs | 736.198 ns | 738.976 ns | 745.008 ns | 741.298 ns | — | — | 1.138 ms | 73.491 μs |
| translation_kernel | Float64 128^3 | 1.827 ms | 1.003 ms | 769.033 μs | 536.206 μs | 1.837 μs | 1.828 μs | 1.845 μs | 1.823 μs | — | — | 1.338 ms | 93.621 μs |
| translation_kernel | Float64 256^3 | 41.093 ms | 8.494 ms | 10.708 ms | 6.716 ms | 3.454 μs | 3.458 μs | 3.469 μs | 3.493 μs | — | — | 2.213 ms | 89.921 μs |
| translation_kernel | Float64 512^3 | — | — | — | — | 6.843 μs | 6.786 μs | 6.815 μs | 6.915 μs | — | — | — | — |
| translation_kernel | Float64 64^3 | 231.216 μs | 101.023 μs | 74.401 μs | 60.787 μs | 922.531 ns | 925.455 ns | 931.192 ns | 938.333 ns | — | — | 1.188 ms | 72.051 μs |
| translation_kernel! | Float32 128^3 | — | — | — | — | 1.367 μs | 1.370 μs | 1.369 μs | 1.366 μs | — | — | — | 63.630 μs |
| translation_kernel! | Float32 256^3 | — | — | — | — | 2.620 μs | 2.618 μs | 2.619 μs | 2.619 μs | — | — | — | 65.661 μs |
| translation_kernel! | Float32 512^3 | — | — | — | — | 5.117 μs | 5.120 μs | 5.110 μs | 5.137 μs | — | — | — | — |
| translation_kernel! | Float32 64^3 | — | — | — | — | 699.514 ns | 700.007 ns | 708.479 ns | 697.924 ns | — | — | — | 72.041 μs |
| translation_kernel! | Float64 128^3 | — | — | — | — | 1.692 μs | 1.707 μs | 1.707 μs | 1.692 μs | — | — | — | 65.241 μs |
| translation_kernel! | Float64 256^3 | — | — | — | — | 3.236 μs | 3.236 μs | 3.244 μs | 3.309 μs | — | — | — | 73.711 μs |
| translation_kernel! | Float64 512^3 | — | — | — | — | 6.354 μs | 6.358 μs | 6.360 μs | 6.456 μs | — | — | — | — |
| translation_kernel! | Float64 64^3 | — | — | — | — | 875.655 ns | 879.109 ns | 875.208 ns | 888.909 ns | — | — | — | 60.970 μs |

## transfer

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom | Float32 128^3 | 28.888 ms | 13.922 ms | 7.765 ms | 4.633 ms | 20.855 ms | 11.115 ms | 5.964 ms | 3.436 ms | 2.280 ms | 4.864 ms | 1.343 ms | 204.432 μs |
| anterpolate! CatmullRom | Float32 256^3 | 436.132 ms | 225.143 ms | 120.356 ms | 75.195 ms | 183.815 ms | 93.677 ms | 46.962 ms | 25.047 ms | — | 17.932 ms | 4.044 ms | 2.895 ms |
| anterpolate! CatmullRom | Float32 512^3 | — | — | — | — | 2.941 s | 1.517 s | 773.032 ms | 442.369 ms | — | — | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.238 ms | 1.913 ms | 1.248 ms | 938.078 μs | 2.519 ms | 1.452 ms | 941.999 μs | 657.637 μs | 116.972 μs | 2.057 ms | 1.220 ms | 104.551 μs |
| anterpolate! CatmullRom | Float64 128^3 | 34.657 ms | 16.258 ms | 8.125 ms | 4.852 ms | 22.159 ms | 11.587 ms | 6.200 ms | 3.543 ms | 2.691 ms | 4.862 ms | 1.628 ms | 228.302 μs |
| anterpolate! CatmullRom | Float64 256^3 | 546.414 ms | 287.805 ms | 165.743 ms | 114.407 ms | 284.966 ms | 140.378 ms | 71.054 ms | 41.589 ms | — | 19.810 ms | 4.795 ms | 4.681 ms |
| anterpolate! CatmullRom | Float64 512^3 | — | — | — | — | 3.340 s | 1.797 s | 928.474 ms | 573.214 ms | — | — | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.389 ms | 1.879 ms | 1.262 ms | 943.395 μs | 2.534 ms | 1.492 ms | 972.580 μs | 698.067 μs | 185.312 μs | 2.004 ms | 1.201 ms | 118.831 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 206.898 ms | 102.438 ms | 54.108 ms | 29.977 ms | 160.037 ms | 80.683 ms | 40.793 ms | 21.851 ms | 12.241 ms | 15.478 ms | 4.182 ms | 992.109 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.398 s | 1.309 s | 748.243 ms | 530.262 ms | 1.303 s | 655.317 ms | 326.403 ms | 169.230 ms | — | 48.567 ms | 18.203 ms | 14.971 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 11.775 s | 6.015 s | 3.019 s | 1.692 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 24.505 ms | 13.324 ms | 8.405 ms | 5.731 ms | 19.886 ms | 10.646 ms | 6.460 ms | 4.353 ms | 486.825 μs | 5.959 ms | 2.191 ms | 326.533 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 229.887 ms | 111.011 ms | 56.260 ms | 31.446 ms | 160.668 ms | 80.828 ms | 40.846 ms | 21.729 ms | 13.808 ms | 16.564 ms | 4.883 ms | 1.156 ms |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.816 s | 1.516 s | 925.966 ms | 682.498 ms | 1.441 s | 723.593 ms | 372.036 ms | 198.700 ms | — | 66.043 ms | 28.833 ms | 24.279 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 12.744 s | 6.595 s | 3.432 s | 2.319 s | — | — | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 25.148 ms | 13.373 ms | 8.536 ms | 5.942 ms | 19.940 ms | 10.787 ms | 6.628 ms | 4.441 ms | 825.268 μs | 5.503 ms | 2.720 ms | 330.363 μs |
| anterpolate! NUFFT | Float32 128^3 | 440.339 ms | 240.566 ms | 162.121 ms | 126.581 ms | 359.079 ms | 181.175 ms | 95.026 ms | 60.391 ms | 20.177 ms | 18.762 ms | 5.604 ms | 2.767 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.637 s | 2.564 s | 1.595 s | 1.215 s | 3.798 s | 1.877 s | 1.067 s | 708.687 ms | — | 120.799 ms | 32.967 ms | 28.479 ms |
| anterpolate! NUFFT | Float32 512^3 | — | — | — | — | 31.210 s | 16.446 s | 9.132 s | 5.588 s | — | — | — | — |
| anterpolate! NUFFT | Float32 64^3 | 33.293 ms | 18.266 ms | 11.751 ms | 8.822 ms | 27.342 ms | 14.616 ms | 8.718 ms | 6.049 ms | 1.989 ms | 6.296 ms | 2.380 ms | 440.874 μs |
| anterpolate! NUFFT | Float64 128^3 | 581.682 ms | 329.204 ms | 231.408 ms | 191.318 ms | 419.018 ms | 223.727 ms | 148.607 ms | 109.509 ms | 30.358 ms | 22.503 ms | 10.016 ms | 6.531 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.457 s | 3.104 s | 2.052 s | 1.678 s | 3.665 s | 2.055 s | 1.267 s | 949.491 ms | — | 160.735 ms | 70.065 ms | 58.125 ms |
| anterpolate! NUFFT | Float64 512^3 | — | — | — | — | 40.286 s | 21.887 s | 12.850 s | 8.632 s | — | — | — | — |
| anterpolate! NUFFT | Float64 64^3 | 40.161 ms | 22.518 ms | 15.032 ms | 11.464 ms | 33.733 ms | 18.181 ms | 10.826 ms | 7.402 ms | 3.892 ms | 8.203 ms | 3.612 ms | 833.659 μs |
| anterpolate! trilinear | Float32 128^3 | 4.520 ms | 2.277 ms | 1.400 ms | 963.981 μs | 4.733 ms | 2.555 ms | 1.414 ms | 856.189 μs | 460.884 μs | 2.018 ms | 990.949 μs | 77.611 μs |
| anterpolate! trilinear | Float32 256^3 | 89.673 ms | 48.898 ms | 28.408 ms | 21.164 ms | 45.425 ms | 23.613 ms | 12.143 ms | 6.866 ms | — | 6.631 ms | 1.780 ms | 729.008 μs |
| anterpolate! trilinear | Float32 512^3 | — | — | — | — | 746.817 ms | 389.536 ms | 206.363 ms | 118.006 ms | — | — | — | — |
| anterpolate! trilinear | Float32 64^3 | 491.280 μs | 331.491 μs | 225.859 μs | 179.253 μs | 370.713 μs | 228.123 μs | 164.282 μs | 124.132 μs | 70.080 μs | 1.565 ms | 1.061 ms | 71.131 μs |
| anterpolate! trilinear | Float64 128^3 | 5.640 ms | 2.855 ms | 1.720 ms | 1.321 ms | 6.007 ms | 3.282 ms | 1.866 ms | 1.150 ms | 596.666 μs | 1.980 ms | 1.202 ms | 94.961 μs |
| anterpolate! trilinear | Float64 256^3 | 97.343 ms | 55.716 ms | 36.209 ms | 29.492 ms | 76.975 ms | 38.837 ms | 20.861 ms | 12.860 ms | — | 6.838 ms | 1.761 ms | 1.119 ms |
| anterpolate! trilinear | Float64 512^3 | — | — | — | — | 778.219 ms | 417.873 ms | 220.964 ms | 140.401 ms | — | — | — | — |
| anterpolate! trilinear | Float64 64^3 | 523.595 μs | 343.748 μs | 259.583 μs | 210.906 μs | 378.554 μs | 238.683 μs | 176.111 μs | 133.181 μs | 83.721 μs | 1.554 ms | 936.908 μs | 78.201 μs |
| interpolate! CatmullRom | Float32 128^3 | 12.564 ms | 6.150 ms | 3.087 ms | 1.711 ms | 5.489 ms | 2.790 ms | 1.395 ms | 734.507 μs | 972.889 μs | 3.140 ms | 1.376 ms | 123.961 μs |
| interpolate! CatmullRom | Float32 256^3 | 298.273 ms | 156.282 ms | 82.104 ms | 53.577 ms | 61.758 ms | 31.403 ms | 15.207 ms | 7.812 ms | — | 14.577 ms | 2.785 ms | 869.858 μs |
| interpolate! CatmullRom | Float32 512^3 | — | — | — | — | 1.832 s | 955.082 ms | 472.795 ms | 266.361 ms | — | — | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.333 ms | 715.329 μs | 437.043 μs | 299.843 μs | 629.446 μs | 332.913 μs | 198.342 μs | 134.351 μs | 101.321 μs | 1.724 ms | 1.188 ms | 78.981 μs |
| interpolate! CatmullRom | Float64 128^3 | 17.215 ms | 7.511 ms | 3.790 ms | 1.989 ms | 5.756 ms | 2.885 ms | 1.467 ms | 776.498 μs | 1.411 ms | 2.789 ms | 1.410 ms | 189.402 μs |
| interpolate! CatmullRom | Float64 256^3 | 326.167 ms | 167.984 ms | 98.558 ms | 65.427 ms | 167.892 ms | 82.896 ms | 40.371 ms | 23.922 ms | — | 12.939 ms | 2.854 ms | 1.718 ms |
| interpolate! CatmullRom | Float64 512^3 | — | — | — | — | 2.022 s | 1.098 s | 555.172 ms | 355.857 ms | — | — | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.418 ms | 755.274 μs | 460.251 μs | 320.814 μs | 675.427 μs | 358.024 μs | 214.382 μs | 148.172 μs | 166.201 μs | 1.759 ms | 1.283 ms | 109.512 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 77.824 ms | 39.254 ms | 19.789 ms | 10.830 ms | 42.657 ms | 21.407 ms | 10.775 ms | 5.658 ms | 5.370 ms | 14.027 ms | 3.038 ms | 471.455 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.545 s | 885.882 ms | 541.871 ms | 353.399 ms | 380.775 ms | 185.155 ms | 91.697 ms | 52.546 ms | — | 30.216 ms | 11.603 ms | 4.724 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | — | — | — | — | 5.350 s | 2.922 s | 1.489 s | 898.316 ms | — | — | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.922 ms | 4.742 ms | 2.891 ms | 1.939 ms | 5.089 ms | 2.692 ms | 1.625 ms | 1.082 ms | 688.416 μs | 3.166 ms | 1.783 ms | 269.262 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 99.290 ms | 48.176 ms | 24.054 ms | 13.184 ms | 41.735 ms | 21.127 ms | 10.586 ms | 5.585 ms | 8.105 ms | 9.517 ms | 2.980 ms | 832.208 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.989 s | 1.100 s | 707.401 ms | 470.630 ms | 624.616 ms | 326.176 ms | 159.100 ms | 94.416 ms | — | 28.103 ms | 10.932 ms | 10.035 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | — | — | — | — | 6.499 s | 3.684 s | 2.057 s | 1.293 s | — | — | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 9.195 ms | 4.828 ms | 2.989 ms | 2.017 ms | 5.296 ms | 2.786 ms | 1.671 ms | 1.120 ms | 911.428 μs | 3.595 ms | 2.314 ms | 321.833 μs |
| interpolate! NUFFT | Float32 128^3 | 343.312 ms | 196.862 ms | 143.368 ms | 99.919 ms | 242.550 ms | 132.567 ms | 75.321 ms | 53.222 ms | 12.723 ms | 16.422 ms | 4.893 ms | 1.897 ms |
| interpolate! NUFFT | Float32 256^3 | 3.806 s | 2.221 s | 1.451 s | 1.054 s | 3.028 s | 1.607 s | 869.288 ms | 638.976 ms | — | 72.243 ms | 26.214 ms | 17.657 ms |
| interpolate! NUFFT | Float32 512^3 | — | — | — | — | 25.003 s | 13.332 s | 7.705 s | 5.010 s | — | — | — | — |
| interpolate! NUFFT | Float32 64^3 | 17.897 ms | 10.623 ms | 7.107 ms | 5.480 ms | 12.268 ms | 6.658 ms | 3.851 ms | 2.549 ms | 1.847 ms | 4.302 ms | 2.275 ms | 414.354 μs |
| interpolate! NUFFT | Float64 128^3 | 456.351 ms | 275.340 ms | 209.942 ms | 177.430 ms | 217.247 ms | 128.426 ms | 99.389 ms | 81.118 ms | 25.361 ms | 18.237 ms | 8.627 ms | 5.528 ms |
| interpolate! NUFFT | Float64 256^3 | 4.178 s | 2.527 s | 1.822 s | 1.457 s | 2.046 s | 1.227 s | 894.357 ms | 770.925 ms | — | 118.516 ms | 56.632 ms | 47.672 ms |
| interpolate! NUFFT | Float64 512^3 | — | — | — | — | 24.750 s | 14.236 s | 8.757 s | 9.813 s | — | — | — | — |
| interpolate! NUFFT | Float64 64^3 | 24.681 ms | 15.168 ms | 11.037 ms | 9.321 ms | 17.892 ms | 9.980 ms | 6.072 ms | 4.289 ms | 3.417 ms | 6.116 ms | 3.003 ms | 943.159 μs |
| interpolate! trilinear | Float32 128^3 | 2.040 ms | 1.064 ms | 548.762 μs | 298.410 μs | 1.322 ms | 667.667 μs | 338.024 μs | 179.742 μs | 255.582 μs | 1.719 ms | 1.094 ms | 61.521 μs |
| interpolate! trilinear | Float32 256^3 | 58.965 ms | 31.153 ms | 16.962 ms | 9.612 ms | 17.825 ms | 8.204 ms | 3.818 ms | 1.871 ms | — | 3.594 ms | 1.280 ms | 258.643 μs |
| interpolate! trilinear | Float32 512^3 | — | — | — | — | 436.461 ms | 251.352 ms | 112.411 ms | 61.766 ms | — | — | — | — |
| interpolate! trilinear | Float32 64^3 | 229.927 μs | 130.069 μs | 79.441 μs | 55.421 μs | 149.372 μs | 80.001 μs | 47.771 μs | 33.250 μs | 65.160 μs | 1.448 ms | 957.585 μs | 54.481 μs |
| interpolate! trilinear | Float64 128^3 | 2.701 ms | 1.303 ms | 684.250 μs | 376.231 μs | 1.372 ms | 691.737 μs | 348.454 μs | 186.741 μs | 325.503 μs | 1.772 ms | 1.092 ms | 83.901 μs |
| interpolate! trilinear | Float64 256^3 | 63.559 ms | 34.975 ms | 21.773 ms | 14.148 ms | 40.467 ms | 19.534 ms | 9.251 ms | 4.754 ms | — | 4.014 ms | 1.595 ms | 411.684 μs |
| interpolate! trilinear | Float64 512^3 | — | — | — | — | 442.772 ms | 238.105 ms | 120.049 ms | 74.618 ms | — | — | — | — |
| interpolate! trilinear | Float64 64^3 | 243.070 μs | 135.937 μs | 83.635 μs | 59.224 μs | 161.312 μs | 86.521 μs | 50.090 μs | 33.770 μs | 65.930 μs | 1.530 ms | 1.083 ms | 65.311 μs |

## reductions

| operation | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 1070 | GPU 6700XT | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.254 ms | 7.184 ms | 7.518 ms | 8.042 ms | 7.032 ms | 5.074 ms | 5.969 ms | 6.108 ms | 2.099 ms | 27.761 ms | 1.656 ms | 292.543 μs |
| co-spectrum vec.vec | Float32 256^3 | 67.299 ms | 48.661 ms | 44.719 ms | 41.361 ms | 55.384 ms | 37.273 ms | 33.013 ms | 30.621 ms | — | 97.666 ms | 3.211 ms | 959.020 μs |
| co-spectrum vec.vec | Float32 512^3 | — | — | — | — | 441.104 ms | 270.373 ms | 191.364 ms | 155.118 ms | — | — | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.066 ms | 1.312 ms | 1.499 ms | 1.608 ms | 906.999 μs | 952.320 μs | 1.207 ms | 1.338 ms | 491.824 μs | 17.761 ms | 1.383 ms | 173.132 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.657 ms | 6.773 ms | 6.126 ms | 5.353 ms | 7.270 ms | 5.273 ms | 4.549 ms | 4.507 ms | 2.194 ms | 29.708 ms | 29.468 ms | 377.103 μs |
| co-spectrum vec.vec | Float64 256^3 | 69.632 ms | 48.804 ms | 36.231 ms | 30.082 ms | 58.759 ms | 38.357 ms | 27.544 ms | 22.862 ms | — | 109.563 ms | 66.321 ms | 1.408 ms |
| co-spectrum vec.vec | Float64 512^3 | — | — | — | — | 465.710 ms | 290.656 ms | 188.164 ms | 137.365 ms | — | — | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.085 ms | 825.029 μs | 980.776 μs | 1.003 ms | 938.490 μs | 768.798 μs | 860.988 μs | 918.730 μs | 482.135 μs | 16.075 ms | 16.001 ms | 191.602 μs |
| cov vector | Float32 128^3 | — | — | — | — | 1.146 ms | 584.046 μs | 306.573 μs | 192.812 μs | — | — | — | 265.903 μs |
| cov vector | Float32 256^3 | — | — | — | — | 12.852 ms | 7.828 ms | 5.569 ms | 5.254 ms | — | — | — | 968.550 μs |
| cov vector | Float32 512^3 | — | — | — | — | 95.861 ms | 64.586 ms | 55.223 ms | 55.507 ms | — | — | — | — |
| cov vector | Float32 64^3 | — | — | — | — | 150.082 μs | 84.801 μs | 51.601 μs | 44.581 μs | — | — | — | 212.302 μs |
| cov vector | Float64 128^3 | — | — | — | — | 2.238 ms | 1.133 ms | 584.636 μs | 341.603 μs | — | — | — | 386.364 μs |
| cov vector | Float64 256^3 | — | — | — | — | 24.015 ms | 16.023 ms | 13.106 ms | 13.257 ms | — | — | — | 1.546 ms |
| cov vector | Float64 512^3 | — | — | — | — | 183.841 ms | 129.790 ms | 111.610 ms | 115.575 ms | — | — | — | — |
| cov vector | Float64 64^3 | — | — | — | — | 281.683 μs | 158.012 μs | 89.041 μs | 65.481 μs | — | — | — | 237.802 μs |
| cross-correlation vec.vec | Float32 128^3 | 39.547 ms | 34.663 ms | 36.194 ms | 38.616 ms | 33.501 ms | 24.848 ms | 22.432 ms | 21.552 ms | 5.891 ms | 43.640 ms | 2.622 ms | 661.337 μs |
| cross-correlation vec.vec | Float32 256^3 | 474.252 ms | 310.305 ms | 279.929 ms | 270.474 ms | 374.940 ms | 276.268 ms | 201.158 ms | 181.189 ms | — | 186.915 ms | 10.470 ms | 5.957 ms |
| cross-correlation vec.vec | Float32 512^3 | — | — | — | — | 3.160 s | 2.021 s | 1.358 s | 1.168 s | — | — | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.749 ms | 5.378 ms | 6.182 ms | 6.182 ms | 3.883 ms | 3.661 ms | 3.739 ms | 3.668 ms | 1.025 ms | 20.682 ms | 1.467 ms | 227.602 μs |
| cross-correlation vec.vec | Float64 128^3 | 62.493 ms | 61.925 ms | 56.674 ms | 51.020 ms | 47.270 ms | 40.258 ms | 27.636 ms | 31.732 ms | 9.144 ms | 52.055 ms | 51.351 ms | 2.081 ms |
| cross-correlation vec.vec | Float64 256^3 | 694.984 ms | 487.096 ms | 402.316 ms | 373.900 ms | 560.272 ms | 390.995 ms | 271.023 ms | 225.202 ms | — | 217.471 ms | 137.382 ms | 16.006 ms |
| cross-correlation vec.vec | Float64 512^3 | — | — | — | — | 4.508 s | 2.989 s | 2.163 s | 1.859 s | — | — | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.865 ms | 5.997 ms | 5.802 ms | 6.028 ms | 4.269 ms | 3.564 ms | 3.372 ms | 3.197 ms | 1.557 ms | 20.881 ms | 23.884 ms | 355.534 μs |
| inner spectral | Float32 128^3 | 2.563 ms | 1.791 ms | 1.452 ms | 1.334 ms | 1.473 ms | 858.358 μs | 538.886 μs | 415.624 μs | 669.926 μs | 2.049 ms | 1.209 ms | 276.522 μs |
| inner spectral | Float32 256^3 | 23.278 ms | 18.210 ms | 16.587 ms | 15.600 ms | 13.577 ms | 8.231 ms | 7.589 ms | 7.663 ms | — | 3.999 ms | 1.750 ms | 772.998 μs |
| inner spectral | Float32 512^3 | — | — | — | — | 111.138 ms | 84.720 ms | 75.654 ms | 76.898 ms | — | — | — | — |
| inner spectral | Float32 64^3 | 311.019 μs | 205.978 μs | 149.325 μs | 120.701 μs | 217.612 μs | 134.131 μs | 95.691 μs | 86.881 μs | 275.972 μs | 1.780 ms | 1.135 ms | 239.382 μs |
| inner spectral | Float64 128^3 | 4.413 ms | 3.674 ms | 3.246 ms | 3.123 ms | 1.992 ms | 1.165 ms | 814.788 μs | 724.508 μs | 811.337 μs | 2.410 ms | 1.363 ms | 374.264 μs |
| inner spectral | Float64 256^3 | 38.299 ms | 32.438 ms | 29.665 ms | 28.720 ms | 20.655 ms | 16.880 ms | 15.812 ms | 16.057 ms | — | 7.953 ms | 2.789 ms | 1.261 ms |
| inner spectral | Float64 512^3 | — | — | — | — | 141.853 ms | 131.473 ms | 128.605 ms | 134.527 ms | — | — | — | — |
| inner spectral | Float64 64^3 | 320.843 μs | 216.120 μs | 156.316 μs | 128.354 μs | 236.343 μs | 143.182 μs | 103.191 μs | 97.901 μs | 293.003 μs | 1.765 ms | 1.138 ms | 239.993 μs |
| inner vec.vec | Float32 128^3 | 1.342 ms | 990.184 μs | 839.085 μs | 784.529 μs | 379.855 μs | 192.252 μs | 100.581 μs | 73.571 μs | 308.353 μs | 1.623 ms | 794.094 μs | 111.971 μs |
| inner vec.vec | Float32 256^3 | 14.293 ms | 12.958 ms | 12.083 ms | 11.385 ms | 7.669 ms | 6.327 ms | 6.133 ms | 6.315 ms | — | 3.382 ms | 1.298 ms | 568.176 μs |
| inner vec.vec | Float32 512^3 | — | — | — | — | 61.781 ms | 57.525 ms | 55.652 ms | 55.886 ms | — | — | — | — |
| inner vec.vec | Float32 64^3 | 70.561 μs | 40.413 μs | 21.692 μs | 15.246 μs | 45.411 μs | 26.080 μs | 14.500 μs | 10.321 μs | 98.731 μs | 1.278 ms | 774.243 μs | 81.461 μs |
| inner vec.vec | Float64 128^3 | 3.170 ms | 2.654 ms | 2.422 ms | 2.283 ms | 1.189 ms | 582.116 μs | 334.533 μs | 255.393 μs | 552.615 μs | 1.860 ms | 998.015 μs | 226.782 μs |
| inner vec.vec | Float64 256^3 | 27.690 ms | 25.846 ms | 24.166 ms | 22.893 ms | 14.999 ms | 13.716 ms | 13.552 ms | 13.657 ms | — | 5.634 ms | 2.038 ms | 1.068 ms |
| inner vec.vec | Float64 512^3 | — | — | — | — | 123.684 ms | 115.213 ms | 111.832 ms | 114.155 ms | — | — | — | — |
| inner vec.vec | Float64 64^3 | 140.726 μs | 79.148 μs | 42.532 μs | 26.139 μs | 88.101 μs | 47.171 μs | 28.040 μs | 18.610 μs | 162.792 μs | 1.434 ms | 777.319 μs | 140.021 μs |
| integral scalar | Float32 128^3 | 111.663 μs | 62.237 μs | 31.233 μs | 20.314 μs | 66.431 μs | 36.860 μs | 20.350 μs | 12.800 μs | 228.932 μs | 1.318 ms | 1.144 ms | 90.211 μs |
| integral scalar | Float32 256^3 | 2.158 ms | 1.576 ms | 1.356 ms | 1.256 ms | 562.146 μs | 315.573 μs | 158.652 μs | 95.541 μs | — | 9.002 ms | 2.302 ms | 254.162 μs |
| integral scalar | Float32 512^3 | — | — | — | — | 9.954 ms | 9.202 ms | 9.052 ms | 9.036 ms | — | — | — | — |
| integral scalar | Float32 64^3 | 9.716 μs | 6.790 μs | 5.853 μs | 6.149 μs | 7.080 μs | 4.718 μs | 4.131 μs | 5.030 μs | 95.301 μs | 1.534 ms | 899.409 μs | 86.011 μs |
| integral scalar | Float64 128^3 | 237.317 μs | 131.226 μs | 68.405 μs | 39.071 μs | 124.421 μs | 63.730 μs | 33.741 μs | 22.971 μs | 221.812 μs | 2.553 ms | 1.192 ms | 92.811 μs |
| integral scalar | Float64 256^3 | 4.624 ms | 3.807 ms | 3.490 ms | 3.241 ms | 2.093 ms | 1.254 ms | 896.649 μs | 992.280 μs | — | 10.817 ms | 2.694 ms | 308.783 μs |
| integral scalar | Float64 512^3 | — | — | — | — | 21.673 ms | 19.046 ms | 17.830 ms | 18.197 ms | — | — | — | — |
| integral scalar | Float64 64^3 | 26.823 μs | 13.214 μs | 8.356 μs | 8.211 μs | 15.230 μs | 7.160 μs | 5.866 μs | 5.670 μs | 95.391 μs | 1.583 ms | 853.383 μs | 90.131 μs |
| integral spectral vec | Float32 128^3 | 73.574 ns | 68.827 ns | 68.706 ns | 69.278 ns | 68.808 ns | 68.987 ns | 68.849 ns | 69.560 ns | — | — | 847.189 μs | 47.651 μs |
| integral spectral vec | Float32 256^3 | 73.413 ns | 68.980 ns | 69.976 ns | 69.051 ns | 68.912 ns | 69.807 ns | 70.834 ns | 69.766 ns | — | — | 812.731 μs | 48.711 μs |
| integral spectral vec | Float32 512^3 | — | — | — | — | 72.459 ns | 68.493 ns | 75.882 ns | 68.628 ns | — | — | — | — |
| integral spectral vec | Float32 64^3 | 72.717 ns | 71.669 ns | 68.260 ns | 68.346 ns | 70.814 ns | 71.967 ns | 68.480 ns | 68.864 ns | — | — | 833.215 μs | 43.790 μs |
| integral spectral vec | Float64 128^3 | 75.348 ns | 70.247 ns | 71.222 ns | 70.787 ns | 71.932 ns | 71.884 ns | 75.792 ns | 76.136 ns | — | — | 832.384 μs | 45.601 μs |
| integral spectral vec | Float64 256^3 | 76.678 ns | 71.125 ns | 71.996 ns | 72.808 ns | 73.597 ns | 74.959 ns | 78.037 ns | 78.572 ns | — | — | 808.714 μs | 51.411 μs |
| integral spectral vec | Float64 512^3 | — | — | — | — | 77.635 ns | 76.809 ns | 89.415 ns | 76.808 ns | — | — | — | — |
| integral spectral vec | Float64 64^3 | 72.326 ns | 69.628 ns | 69.560 ns | 70.826 ns | 75.363 ns | 74.179 ns | 78.020 ns | 78.468 ns | — | — | 842.906 μs | 56.451 μs |
| l2norm vec | Float32 128^3 | 640.793 μs | 338.018 μs | 186.032 μs | 92.844 μs | 239.933 μs | 128.481 μs | 69.601 μs | 40.400 μs | 196.632 μs | 1.582 ms | 854.011 μs | 82.510 μs |
| l2norm vec | Float32 256^3 | 8.328 ms | 6.167 ms | 5.599 ms | 5.442 ms | 4.289 ms | 2.552 ms | 2.049 ms | 2.073 ms | — | 3.219 ms | 1.301 ms | 351.033 μs |
| l2norm vec | Float32 512^3 | — | — | — | — | 42.121 ms | 30.714 ms | 26.995 ms | 26.871 ms | — | — | — | — |
| l2norm vec | Float32 64^3 | 50.794 μs | 27.610 μs | 15.886 μs | 11.830 μs | 31.220 μs | 16.920 μs | 9.730 μs | 7.491 μs | 85.641 μs | 1.361 ms | 756.839 μs | 75.591 μs |
| l2norm vec | Float64 128^3 | 1.712 ms | 1.077 ms | 827.080 μs | 779.411 μs | 554.695 μs | 236.083 μs | 133.372 μs | 83.791 μs | 344.333 μs | 1.876 ms | 978.559 μs | 147.432 μs |
| l2norm vec | Float64 256^3 | 15.793 ms | 12.600 ms | 11.618 ms | 11.037 ms | 11.408 ms | 7.073 ms | 5.842 ms | 5.705 ms | — | 5.670 ms | 1.957 ms | 600.956 μs |
| l2norm vec | Float64 512^3 | — | — | — | — | 73.555 ms | 61.978 ms | 54.684 ms | 55.492 ms | — | — | — | — |
| l2norm vec | Float64 64^3 | 94.189 μs | 53.113 μs | 28.482 μs | 18.489 μs | 55.261 μs | 29.060 μs | 16.860 μs | 11.160 μs | 134.871 μs | 1.402 ms | 773.034 μs | 119.911 μs |
| lpnorm vec Inf | Float32 128^3 | 1.389 ms | 1.370 ms | 1.146 ms | 1.040 ms | 461.115 μs | 403.245 μs | 347.493 μs | 346.324 μs | 592.145 μs | 3.080 ms | 1.319 ms | 135.491 μs |
| lpnorm vec Inf | Float32 256^3 | 22.791 ms | 14.822 ms | 12.193 ms | 11.084 ms | 8.370 ms | 8.005 ms | 8.159 ms | 7.988 ms | — | 13.216 ms | 3.421 ms | 601.976 μs |
| lpnorm vec Inf | Float32 512^3 | — | — | — | — | 77.736 ms | 68.034 ms | 72.517 ms | 73.667 ms | — | — | — | — |
| lpnorm vec Inf | Float32 64^3 | 98.887 μs | 92.210 μs | 73.501 μs | 78.929 μs | 62.320 μs | 50.280 μs | 42.761 μs | 42.711 μs | 155.751 μs | 1.641 ms | 964.230 μs | 108.241 μs |
| lpnorm vec Inf | Float64 128^3 | 3.310 ms | 3.191 ms | 2.602 ms | 2.600 ms | 1.157 ms | 1.038 ms | 999.030 μs | 1.068 ms | 660.476 μs | 3.883 ms | 1.668 ms | 233.423 μs |
| lpnorm vec Inf | Float64 256^3 | 47.266 ms | 31.386 ms | 24.155 ms | 22.468 ms | 17.645 ms | 15.442 ms | 15.529 ms | 16.734 ms | — | 14.730 ms | 5.382 ms | 974.520 μs |
| lpnorm vec Inf | Float64 512^3 | — | — | — | — | 155.420 ms | 169.106 ms | 141.977 ms | 142.843 ms | — | — | — | — |
| lpnorm vec Inf | Float64 64^3 | 238.281 μs | 179.555 μs | 154.396 μs | 145.295 μs | 111.511 μs | 93.921 μs | 77.370 μs | 72.451 μs | 166.092 μs | 1.711 ms | 1.005 ms | 119.902 μs |
| maximum scalar | Float32 128^3 | 345.259 μs | 177.509 μs | 92.029 μs | 51.200 μs | 237.983 μs | 120.622 μs | 61.681 μs | 33.261 μs | 223.322 μs | 2.331 ms | 1.146 ms | 90.741 μs |
| maximum scalar | Float32 256^3 | 2.903 ms | 1.818 ms | 1.454 ms | 1.335 ms | 1.942 ms | 948.990 μs | 488.935 μs | 246.592 μs | — | 9.121 ms | 2.319 ms | 244.253 μs |
| maximum scalar | Float32 512^3 | — | — | — | — | 26.204 ms | 14.510 ms | 9.144 ms | 8.075 ms | — | — | — | — |
| maximum scalar | Float32 64^3 | 43.017 μs | 24.700 μs | 14.813 μs | 11.942 μs | 29.511 μs | 15.950 μs | 9.300 μs | 6.720 μs | 101.731 μs | 1.564 ms | 922.422 μs | 81.170 μs |
| maximum scalar | Float64 128^3 | 547.286 μs | 291.499 μs | 144.142 μs | 79.381 μs | 438.524 μs | 225.062 μs | 114.411 μs | 59.670 μs | 244.072 μs | 2.772 ms | 1.301 ms | 101.591 μs |
| maximum scalar | Float64 256^3 | 6.082 ms | 4.302 ms | 3.627 ms | 3.355 ms | 4.203 ms | 2.071 ms | 1.102 ms | 877.458 μs | — | 12.659 ms | 3.329 ms | 299.793 μs |
| maximum scalar | Float64 512^3 | — | — | — | — | 45.590 ms | 27.338 ms | 18.852 ms | 17.889 ms | — | — | — | — |
| maximum scalar | Float64 64^3 | 66.519 μs | 37.472 μs | 20.447 μs | 14.675 μs | 55.670 μs | 28.941 μs | 16.340 μs | 10.140 μs | 99.451 μs | 1.634 ms | 947.833 μs | 93.101 μs |
| maximum(norm) vec | Float32 128^3 | 1.840 ms | 927.308 μs | 474.221 μs | 246.021 μs | 774.209 μs | 390.504 μs | 200.372 μs | 106.131 μs | — | — | 1.234 ms | 102.231 μs |
| maximum(norm) vec | Float32 256^3 | 15.152 ms | 8.494 ms | 5.995 ms | 5.604 ms | 6.950 ms | 4.017 ms | 2.572 ms | 2.237 ms | — | — | 2.782 ms | 363.864 μs |
| maximum(norm) vec | Float32 512^3 | — | — | — | — | 65.971 ms | 39.018 ms | 29.630 ms | 27.985 ms | — | — | — | — |
| maximum(norm) vec | Float32 64^3 | 225.159 μs | 118.554 μs | 62.180 μs | 48.872 μs | 96.601 μs | 49.660 μs | 26.531 μs | 15.470 μs | — | — | 920.168 μs | 92.271 μs |
| maximum(norm) vec | Float64 128^3 | 5.345 ms | 2.715 ms | 1.393 ms | 846.954 μs | 1.591 ms | 795.778 μs | 401.254 μs | 207.373 μs | — | — | 1.571 ms | 219.472 μs |
| maximum(norm) vec | Float64 256^3 | 43.178 ms | 22.282 ms | 13.330 ms | 11.568 ms | 14.291 ms | 8.332 ms | 6.437 ms | 6.058 ms | — | — | 4.860 ms | 1.059 ms |
| maximum(norm) vec | Float64 512^3 | — | — | — | — | 123.406 ms | 73.546 ms | 58.509 ms | 57.318 ms | — | — | — | — |
| maximum(norm) vec | Float64 64^3 | 651.615 μs | 337.108 μs | 170.646 μs | 90.136 μs | 197.392 μs | 100.531 μs | 52.180 μs | 28.690 μs | — | — | 979.833 μs | 103.122 μs |
| mean spectral vec | Float32 128^3 | 71.740 ns | 71.533 ns | 71.579 ns | 72.110 ns | 71.562 ns | 71.299 ns | 73.091 ns | 73.179 ns | — | — | 820.577 μs | 45.301 μs |
| mean spectral vec | Float32 256^3 | 72.239 ns | 72.320 ns | 72.756 ns | 72.872 ns | 71.921 ns | 72.156 ns | 74.245 ns | 74.309 ns | — | — | 812.941 μs | 48.021 μs |
| mean spectral vec | Float32 512^3 | — | — | — | — | 74.323 ns | 75.245 ns | 85.586 ns | 71.974 ns | — | — | — | — |
| mean spectral vec | Float32 64^3 | 77.463 ns | 71.234 ns | 71.368 ns | 71.759 ns | 73.105 ns | 72.787 ns | 72.804 ns | 72.781 ns | — | — | 833.055 μs | 46.341 μs |
| mean spectral vec | Float64 128^3 | 77.758 ns | 73.848 ns | 74.286 ns | 74.398 ns | 76.729 ns | 77.283 ns | 78.486 ns | 79.475 ns | — | — | 814.812 μs | 46.601 μs |
| mean spectral vec | Float64 256^3 | 79.716 ns | 74.563 ns | 75.460 ns | 76.613 ns | 80.165 ns | 79.181 ns | 79.731 ns | 82.480 ns | — | — | 848.819 μs | 48.480 μs |
| mean spectral vec | Float64 512^3 | — | — | — | — | 81.663 ns | 80.279 ns | 82.248 ns | 82.558 ns | — | — | — | — |
| mean spectral vec | Float64 64^3 | 73.504 ns | 73.021 ns | 72.737 ns | 73.951 ns | 80.581 ns | 79.637 ns | 81.136 ns | 81.583 ns | — | — | 830.467 μs | 56.291 μs |
| mean vector | Float32 128^3 | 521.620 μs | 319.670 μs | 194.991 μs | 114.663 μs | 203.582 μs | 110.911 μs | 68.371 μs | 54.230 μs | 633.756 μs | 4.808 ms | 1.887 ms | 198.152 μs |
| mean vector | Float32 256^3 | 7.827 ms | 6.072 ms | 5.559 ms | 5.436 ms | 3.027 ms | 2.537 ms | 2.527 ms | 2.698 ms | — | 16.657 ms | 5.531 ms | 655.757 μs |
| mean vector | Float32 512^3 | — | — | — | — | 31.634 ms | 27.409 ms | 26.978 ms | 27.377 ms | — | — | — | — |
| mean vector | Float32 64^3 | 49.165 μs | 34.264 μs | 25.674 μs | 31.341 μs | 32.590 μs | 22.650 μs | 17.730 μs | 22.580 μs | 162.362 μs | 1.846 ms | 1.302 ms | 165.232 μs |
| mean vector | Float64 128^3 | 1.648 ms | 1.053 ms | 849.643 μs | 793.726 μs | 411.715 μs | 215.502 μs | 118.491 μs | 90.181 μs | 657.486 μs | 5.195 ms | 1.836 ms | 213.492 μs |
| mean vector | Float64 256^3 | 14.983 ms | 12.972 ms | 11.806 ms | 11.316 ms | 7.625 ms | 7.186 ms | 6.831 ms | 6.705 ms | — | 17.799 ms | 6.369 ms | 712.827 μs |
| mean vector | Float64 512^3 | — | — | — | — | 59.765 ms | 56.466 ms | 54.734 ms | 56.642 ms | — | — | — | — |
| mean vector | Float64 64^3 | 92.415 μs | 63.766 μs | 41.668 μs | 40.850 μs | 55.151 μs | 38.790 μs | 26.680 μs | 26.410 μs | 156.311 μs | 1.913 ms | 1.281 ms | 170.362 μs |
| mean(det) tensor | Float32 128^3 | 2.495 ms | 1.968 ms | 1.694 ms | 1.532 ms | 785.659 μs | 385.524 μs | 190.492 μs | 128.631 μs | — | — | 1.280 ms | 221.092 μs |
| mean(det) tensor | Float32 256^3 | 24.807 ms | 21.499 ms | 19.098 ms | 17.978 ms | 16.093 ms | 11.859 ms | 10.582 ms | 10.744 ms | — | — | 3.413 ms | 835.548 μs |
| mean(det) tensor | Float32 512^3 | — | — | — | — | 112.880 ms | 89.708 ms | 83.822 ms | 85.650 ms | — | — | — | — |
| mean(det) tensor | Float32 64^3 | 103.122 μs | 61.466 μs | 29.994 μs | 21.224 μs | 68.081 μs | 37.570 μs | 23.140 μs | 15.820 μs | — | — | 937.045 μs | 94.811 μs |
| mean(det) tensor | Float64 128^3 | 5.384 ms | 4.754 ms | 4.222 ms | 3.863 ms | 2.678 ms | 1.593 ms | 1.227 ms | 1.281 ms | — | — | 1.491 ms | 284.932 μs |
| mean(det) tensor | Float64 256^3 | 46.354 ms | 44.532 ms | 38.506 ms | 37.166 ms | 30.490 ms | 23.974 ms | 21.868 ms | 21.965 ms | — | — | 4.560 ms | 1.537 ms |
| mean(det) tensor | Float64 512^3 | — | — | — | — | 199.621 ms | 180.266 ms | 171.787 ms | 177.815 ms | — | — | — | — |
| mean(det) tensor | Float64 64^3 | 233.464 μs | 129.918 μs | 74.662 μs | 41.508 μs | 129.391 μs | 68.131 μs | 44.180 μs | 28.850 μs | — | — | 972.637 μs | 100.671 μs |
| mean(norm) vec | Float32 128^3 | 1.589 ms | 806.356 μs | 407.919 μs | 212.917 μs | 612.207 μs | 305.153 μs | 159.982 μs | 84.541 μs | — | — | 538.869 μs | 107.601 μs |
| mean(norm) vec | Float32 256^3 | 13.152 ms | 7.866 ms | 5.982 ms | 5.545 ms | 6.024 ms | 3.425 ms | 2.659 ms | 2.234 ms | — | — | 2.833 ms | 367.844 μs |
| mean(norm) vec | Float32 512^3 | — | — | — | — | 58.847 ms | 36.713 ms | 29.470 ms | 28.062 ms | — | — | — | — |
| mean(norm) vec | Float32 64^3 | 193.009 μs | 99.359 μs | 53.467 μs | 31.969 μs | 76.211 μs | 39.780 μs | 21.210 μs | 16.220 μs | — | — | 921.051 μs | 84.891 μs |
| mean(norm) vec | Float64 128^3 | 5.283 ms | 2.668 ms | 1.367 ms | 852.780 μs | 1.449 ms | 720.188 μs | 361.624 μs | 190.562 μs | — | — | 1.332 ms | 205.922 μs |
| mean(norm) vec | Float64 256^3 | 42.797 ms | 21.618 ms | 13.196 ms | 11.503 ms | 14.009 ms | 7.801 ms | 6.243 ms | 6.029 ms | — | — | 4.325 ms | 951.569 μs |
| mean(norm) vec | Float64 512^3 | — | — | — | — | 109.761 ms | 71.251 ms | 57.710 ms | 57.382 ms | — | — | — | — |
| mean(norm) vec | Float64 64^3 | 644.557 μs | 332.750 μs | 168.447 μs | 89.317 μs | 178.782 μs | 91.441 μs | 47.670 μs | 26.400 μs | — | — | 957.695 μs | 98.531 μs |
| mean(tr) tensor | Float32 128^3 | 376.803 μs | 234.813 μs | 139.321 μs | 73.191 μs | 193.742 μs | 96.591 μs | 50.690 μs | 37.651 μs | — | — | 1.200 ms | 111.381 μs |
| mean(tr) tensor | Float32 256^3 | 6.684 ms | 6.358 ms | 5.667 ms | 5.460 ms | 3.296 ms | 2.410 ms | 2.258 ms | 2.324 ms | — | — | 2.699 ms | 354.544 μs |
| mean(tr) tensor | Float32 512^3 | — | — | — | — | 35.884 ms | 28.959 ms | 27.510 ms | 28.149 ms | — | — | — | — |
| mean(tr) tensor | Float32 64^3 | 34.871 μs | 18.654 μs | 11.294 μs | 10.156 μs | 25.521 μs | 13.031 μs | 7.660 μs | 6.760 μs | — | — | 910.276 μs | 81.451 μs |
| mean(tr) tensor | Float64 128^3 | 1.325 ms | 985.412 μs | 838.504 μs | 748.239 μs | 396.584 μs | 181.462 μs | 95.311 μs | 73.791 μs | — | — | 1.170 ms | 136.882 μs |
| mean(tr) tensor | Float64 256^3 | 13.247 ms | 13.083 ms | 11.902 ms | 11.275 ms | 7.059 ms | 6.739 ms | 6.505 ms | 6.535 ms | — | — | 3.285 ms | 590.546 μs |
| mean(tr) tensor | Float64 512^3 | — | — | — | — | 64.808 ms | 59.963 ms | 56.735 ms | 58.231 ms | — | — | — | — |
| mean(tr) tensor | Float64 64^3 | 67.856 μs | 37.556 μs | 20.285 μs | 15.147 μs | 42.571 μs | 25.590 μs | 14.640 μs | 9.830 μs | — | — | 921.594 μs | 95.511 μs |
| radial_correlation vec | Float32 128^3 | 37.712 ms | 33.033 ms | 35.793 ms | 36.040 ms | 30.874 ms | 23.149 ms | 21.319 ms | 20.811 ms | 5.783 ms | 42.875 ms | 2.515 ms | 637.917 μs |
| radial_correlation vec | Float32 256^3 | 447.565 ms | 308.865 ms | 277.883 ms | 264.189 ms | 352.975 ms | 246.249 ms | 195.662 ms | 174.433 ms | — | 185.439 ms | 10.286 ms | 5.640 ms |
| radial_correlation vec | Float32 512^3 | — | — | — | — | 2.961 s | 1.886 s | 1.333 s | 1.172 s | — | — | — | — |
| radial_correlation vec | Float32 64^3 | 4.485 ms | 5.199 ms | 5.976 ms | 5.911 ms | 3.559 ms | 3.263 ms | 3.620 ms | 3.568 ms | 1.010 ms | 19.917 ms | 1.555 ms | 228.812 μs |
| radial_correlation vec | Float64 128^3 | 60.402 ms | 62.099 ms | 54.644 ms | 51.117 ms | 45.835 ms | 35.872 ms | 26.282 ms | 31.324 ms | 9.025 ms | 52.060 ms | 47.229 ms | 2.038 ms |
| radial_correlation vec | Float64 256^3 | 673.902 ms | 474.417 ms | 394.981 ms | 361.825 ms | 550.453 ms | 371.716 ms | 284.470 ms | 236.689 ms | — | 219.151 ms | 138.359 ms | 14.789 ms |
| radial_correlation vec | Float64 512^3 | — | — | — | — | 4.344 s | 2.859 s | 2.031 s | 1.780 s | — | — | — | — |
| radial_correlation vec | Float64 64^3 | 5.555 ms | 5.140 ms | 5.663 ms | 5.733 ms | 3.893 ms | 3.299 ms | 3.286 ms | 3.249 ms | 1.413 ms | 21.203 ms | 23.553 ms | 350.804 μs |
| radial_spectrum vec | Float32 128^3 | 7.687 ms | 7.368 ms | 8.086 ms | 8.080 ms | 6.341 ms | 4.784 ms | 5.779 ms | 6.328 ms | 1.415 ms | 27.166 ms | 1.792 ms | 283.923 μs |
| radial_spectrum vec | Float32 256^3 | 61.536 ms | 48.600 ms | 45.891 ms | 43.702 ms | 50.263 ms | 33.846 ms | 31.201 ms | 31.986 ms | — | 96.772 ms | 3.246 ms | 950.540 μs |
| radial_spectrum vec | Float32 512^3 | — | — | — | — | 399.780 ms | 239.682 ms | 180.331 ms | 152.778 ms | — | — | — | — |
| radial_spectrum vec | Float32 64^3 | 998.613 μs | 1.333 ms | 1.599 ms | 1.621 ms | 821.828 μs | 912.749 μs | 1.153 ms | 1.348 ms | 344.443 μs | 16.995 ms | 1.190 ms | 166.962 μs |
| radial_spectrum vec | Float64 128^3 | 7.731 ms | 6.612 ms | 5.934 ms | 5.548 ms | 6.552 ms | 4.658 ms | 4.401 ms | 4.392 ms | 1.515 ms | 29.791 ms | 28.854 ms | 385.124 μs |
| radial_spectrum vec | Float64 256^3 | 62.255 ms | 46.066 ms | 36.465 ms | 30.301 ms | 52.089 ms | 32.586 ms | 25.467 ms | 22.802 ms | — | 110.504 ms | 67.077 ms | 1.380 ms |
| radial_spectrum vec | Float64 512^3 | — | — | — | — | 414.239 ms | 255.623 ms | 166.863 ms | 129.362 ms | — | — | — | — |
| radial_spectrum vec | Float64 64^3 | 1.008 ms | 774.067 μs | 1.104 ms | 1.102 ms | 847.849 μs | 698.128 μs | 836.078 μs | 886.169 μs | 380.613 μs | 16.740 ms | 15.470 ms | 190.852 μs |
| var scalar | Float32 128^3 | — | — | — | — | 138.341 μs | 75.481 μs | 42.670 μs | 27.840 μs | — | — | — | 138.351 μs |
| var scalar | Float32 256^3 | — | — | — | — | 1.195 ms | 655.727 μs | 327.413 μs | 201.202 μs | — | — | — | 441.165 μs |
| var scalar | Float32 512^3 | — | — | — | — | 24.326 ms | 20.062 ms | 18.194 ms | 18.097 ms | — | — | — | — |
| var scalar | Float32 64^3 | — | — | — | — | 15.020 μs | 8.950 μs | 7.260 μs | 9.210 μs | — | — | — | 120.531 μs |
| var scalar | Float64 128^3 | — | — | — | — | 252.253 μs | 130.241 μs | 69.391 μs | 49.411 μs | — | — | — | 148.531 μs |
| var scalar | Float64 256^3 | — | — | — | — | 4.531 ms | 2.666 ms | 1.839 ms | 1.911 ms | — | — | — | 485.235 μs |
| var scalar | Float64 512^3 | — | — | — | — | 49.422 ms | 39.912 ms | 36.185 ms | 37.610 ms | — | — | — | — |
| var scalar | Float64 64^3 | — | — | — | — | 32.170 μs | 17.410 μs | 11.100 μs | 12.061 μs | — | — | — | 131.222 μs |
| var spectral scalar | Float32 128^3 | — | — | — | — | 91.801 μs | 61.640 μs | 43.711 μs | 41.021 μs | — | — | — | 168.572 μs |
| var spectral scalar | Float32 256^3 | — | — | — | — | 760.928 μs | 459.755 μs | 289.233 μs | 248.023 μs | — | — | — | 307.563 μs |
| var spectral scalar | Float32 512^3 | — | — | — | — | 14.877 ms | 9.936 ms | 9.968 ms | 10.969 ms | — | — | — | — |
| var spectral scalar | Float32 64^3 | — | — | — | — | 12.170 μs | 8.430 μs | 7.720 μs | 10.440 μs | — | — | — | 182.451 μs |
| var spectral scalar | Float64 128^3 | — | — | — | — | 161.431 μs | 88.871 μs | 63.831 μs | 56.121 μs | — | — | — | 172.371 μs |
| var spectral scalar | Float64 256^3 | — | — | — | — | 2.205 ms | 1.381 ms | 1.076 ms | 1.133 ms | — | — | — | 353.694 μs |
| var spectral scalar | Float64 512^3 | — | — | — | — | 21.111 ms | 20.242 ms | 20.249 ms | 20.909 ms | — | — | — | — |
| var spectral scalar | Float64 64^3 | — | — | — | — | 21.040 μs | 13.130 μs | 10.170 μs | 10.070 μs | — | — | — | 179.132 μs |
| weighted_inner vec | Float32 128^3 | 12.776 ms | 12.629 ms | 12.608 ms | 12.786 ms | 10.400 ms | 10.379 ms | 10.359 ms | 10.345 ms | — | — | 1.428 ms | 141.521 μs |
| weighted_inner vec | Float32 256^3 | 100.807 ms | 100.234 ms | 99.130 ms | 100.881 ms | 81.520 ms | 81.560 ms | 81.646 ms | 81.574 ms | — | — | 4.280 ms | 641.987 μs |
| weighted_inner vec | Float32 512^3 | — | — | — | — | 646.180 ms | 648.607 ms | 647.256 ms | 645.225 ms | — | — | — | — |
| weighted_inner vec | Float32 64^3 | 1.629 ms | 1.624 ms | 1.626 ms | 1.629 ms | 1.282 ms | 1.282 ms | 1.280 ms | 1.280 ms | — | — | 1.020 ms | 94.491 μs |
| weighted_inner vec | Float64 128^3 | 13.991 ms | 13.956 ms | 13.886 ms | 13.759 ms | 10.912 ms | 10.939 ms | 10.965 ms | 10.907 ms | — | — | 1.679 ms | 166.751 μs |
| weighted_inner vec | Float64 256^3 | 110.973 ms | 111.552 ms | 111.245 ms | 108.115 ms | 85.928 ms | 86.103 ms | 85.903 ms | 86.140 ms | — | — | 5.232 ms | 1.075 ms |
| weighted_inner vec | Float64 512^3 | — | — | — | — | 680.354 ms | 681.039 ms | 684.343 ms | 689.549 ms | — | — | — | — |
| weighted_inner vec | Float64 64^3 | 1.725 ms | 1.725 ms | 1.722 ms | 1.715 ms | 1.357 ms | 1.361 ms | 1.427 ms | 1.354 ms | — | — | 1.040 ms | 107.331 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.869 ms | 12.646 ms | 12.697 ms | 12.786 ms | 10.361 ms | 10.485 ms | 10.420 ms | 10.362 ms | — | — | 1.362 ms | 158.782 μs |
| weighted_inner vec.vec | Float32 256^3 | 101.877 ms | 100.494 ms | 99.619 ms | 101.362 ms | 81.718 ms | 81.993 ms | 82.088 ms | 81.746 ms | — | — | 4.195 ms | 832.649 μs |
| weighted_inner vec.vec | Float32 512^3 | — | — | — | — | 643.648 ms | 649.567 ms | 648.538 ms | 649.121 ms | — | — | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.632 ms | 1.626 ms | 1.628 ms | 1.599 ms | 1.287 ms | 1.286 ms | 1.287 ms | 1.295 ms | — | — | 1.001 ms | 102.951 μs |
| weighted_inner vec.vec | Float64 128^3 | 14.076 ms | 14.115 ms | 14.233 ms | 13.824 ms | 10.961 ms | 11.019 ms | 10.968 ms | 10.950 ms | — | — | 1.584 ms | 260.652 μs |
| weighted_inner vec.vec | Float64 256^3 | 112.210 ms | 112.428 ms | 114.038 ms | 110.747 ms | 86.102 ms | 86.459 ms | 86.361 ms | 86.273 ms | — | — | 5.332 ms | 1.542 ms |
| weighted_inner vec.vec | Float64 512^3 | — | — | — | — | 683.167 ms | 683.008 ms | 780.104 ms | 790.752 ms | — | — | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.743 ms | 1.729 ms | 1.743 ms | 1.705 ms | 1.388 ms | 1.377 ms | 1.435 ms | 1.399 ms | — | — | 985.284 μs | 103.281 μs |

