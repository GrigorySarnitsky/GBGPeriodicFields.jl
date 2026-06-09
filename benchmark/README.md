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
- `fft.jl`, `algebra.jl`, `operators.jl`, `transfer.jl` — per-class benchmark builders.
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

GPU (ROCm), one-time instantiate then run:
```
julia --project=benchmark/gpu/rocm -e 'using Pkg; Pkg.instantiate()'
julia --project=benchmark/gpu/rocm benchmark/gpu/rocm/runbenchmarks.jl
```

A larger characterisation sweep (the 256³/512³ numbers in `docs/PERFORMANCE.md` §4): pass
`sizes` to `build_suite`, e.g. `build_suite(; sizes = (256,))`.

## Coverage contract

Every public operation is benchmarked over {Float64, Float32} × {representative grid sizes} ×
{CPU `-t1`, CPU `-t4`, GPU}. New operations add their benchmark to the matching per-class file —
the performance analogue of the test coverage contract (`docs/TESTING.md` §4).
