# Benchmarks

A standing benchmark suite (sibling of `test/`), **opt-in** — not part of `Pkg.test()`. It tracks
performance of the public operation classes across platforms. Rationale, methodology, best
practices, and the recorded per-platform results live in [`docs/PERFORMANCE.md`](../docs/PERFORMANCE.md).

## Layout

- `benchmarks.jl` — `build_suite(; array_type, types, sizes)` builds a `BenchmarkTools.BenchmarkGroup`
  parameterised by the device array type (`Array` on CPU; `ROCArray`/`CuArray` on GPU), element type,
  and grid size. `print_results` prints a min-time/allocations table.
- `harness.jl` — device-parameterised field/point builders + `bench_sync` (blocks the backend so
  BenchmarkTools times GPU work to completion).
- `fft.jl`, `algebra.jl`, `operators.jl`, `transfer.jl`, `reductions.jl` — per-class benchmark builders.
- `runbenchmarks.jl` — CPU entry (run, print, optional `save`/`judge`).
- `threading.jl` — standalone serial-vs-threaded comparison (manual).
- `gpu/<backend>/` — per-backend GPU entry (mirrors `test/gpu/`).

## Running

One-time: `julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'`

CPU (run both lanes, matching the CI matrix):
```
julia --project=benchmark -t1 benchmark/runbenchmarks.jl
julia --project=benchmark -t4 benchmark/runbenchmarks.jl
```

Save a baseline, then judge a later run against it (manual regression check):
```
julia --project=benchmark benchmark/runbenchmarks.jl save results/cpu-baseline.json
julia --project=benchmark benchmark/runbenchmarks.jl judge results/cpu-baseline.json
```

### A `-t8` CPU characterization lane segfaults on `Enteropia` — run it split by grid

A single `characterize.jl` process at `-t8` dies with `signal 11` inside FFTW's threaded executor
(`spawn_apply` ← FFTW.jl's `spawnloop`) partway through the `reductions` class. It has failed four of
five attempts on that host and has never been seen on `Aiporetne`; the package itself is fine at eight
threads (`Pkg.test()` passes in full there). Full account, including the four reproduction attempts
that came back clean, in `docs/PERFORMANCE.md` §4(q).

Run the lane as one process per grid and merge the parts — 64³, 256³ and 512³ pass first time, 128³
usually needs a retry:
```
for N in 64 128 256 512; do
  CHAR_SIZES=$N julia -t8 --project=benchmark benchmark/characterize.jl cpu results/t8-part-$N.json
done
```
Each part holds only its own grid's rows, so the union is disjoint and merging them with
`BenchmarkTools.load`/`save` gives exactly what one uncrashed process would have written. Do not reach
for `set_fft_threads!(1)`: it removes the callback and the crash with it, but this lane exists to
measure threaded FFT, so it would corrupt the column it is meant to produce.

GPU (ROCm), one-time instantiate then run:
```
julia --project=benchmark/gpu/rocm -e 'using Pkg; Pkg.instantiate()'
julia --project=benchmark/gpu/rocm benchmark/gpu/rocm/runbenchmarks.jl
```

## The exhaustive report

`runbenchmarks.jl` above is the quick, regression-sensitive run (grids 64³/128³). For the **full
matrix** — the CPU thread sweep (1/2/4/8) and the GPU, over each backend's default grids (CPU
64³–512³, device 64³–256³) and every op-class,
run one grid size at a time to bound memory — use the driver:

```sh
bash benchmark/characterize.sh                    # writes benchmark/RESULTS.md (~15-30 min)
THREADS="1 2 4 8 16" bash benchmark/characterize.sh   # override the thread set
```

It saves per-run JSON under `benchmark/results/` (gitignored) and assembles the committed
`benchmark/RESULTS.md` (full table + provenance) via `benchmark/report.jl`. `characterize.jl` is the
per-launch runner (backend chosen by its first argument, `cpu`/`gpu`).

## Coverage contract

Every public operation is benchmarked over {Float64, Float32} × {representative grid sizes} ×
{CPU `-t1`, CPU `-t4`, GPU}. New operations add their benchmark to the matching per-class file —
the performance analogue of the test coverage contract (`docs/TESTING.md` §4).
