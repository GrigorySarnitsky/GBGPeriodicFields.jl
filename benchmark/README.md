# Benchmarks

PF's benchmark suite, separate from `Pkg.test()` and run only on request. The performance model, the
recorded findings and the per-platform results are in [`docs/PERFORMANCE.md`](../docs/PERFORMANCE.md);
the full results table is [`RESULTS.md`](RESULTS.md).

A benchmark run owns the machine: nothing else runs while it measures, and a GPU run needs an idle card.

## Setup

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'            # CPU
julia --project=benchmark/gpu/cuda -e 'using Pkg; Pkg.instantiate()'   # NVIDIA
julia --project=benchmark/gpu/rocm -e 'using Pkg; Pkg.instantiate()'   # AMD
```

## The four ways to run it

- **Check that every row runs** (seconds; needs no idle machine). Builds every benchmark at a tiny
  grid and runs it once:
  ```sh
  julia --project=benchmark benchmark/gate.jl
  julia --project=benchmark/gpu/cuda benchmark/gate.jl cuda
  julia --project=benchmark/gpu/rocm benchmark/gate.jl rocm
  ```
- **The canary** (minutes). One benchmark per execution mechanism, judged against this host's frozen
  baseline in `baselines/`; it exits nonzero on a regression. `--freeze` writes a new baseline, which
  is committed with its reason.
  ```sh
  julia --project=benchmark -t1 benchmark/regress.jl cpu
  julia --project=benchmark -t8 benchmark/regress.jl cpu
  julia --project=benchmark/gpu/cuda benchmark/regress.jl cuda
  julia --project=benchmark/gpu/rocm benchmark/regress.jl gpu
  ```
- **A quick run** at small grids, with an optional saved baseline to judge a later run against:
  ```sh
  julia --project=benchmark -t4 benchmark/runbenchmarks.jl
  julia --project=benchmark -t4 benchmark/runbenchmarks.jl save results/baseline.json
  julia --project=benchmark -t4 benchmark/runbenchmarks.jl judge results/baseline.json
  ```
  The GPU equivalents are `benchmark/gpu/<backend>/runbenchmarks.jl`.
- **The full sweep** behind `RESULTS.md` (hours). Every class over the CPU thread counts 1, 2, 4 and 8
  and one GPU. `characterize.jl` measures one lane into an archive under `results/`, and `report.jl`
  assembles all ten archives, both hosts', into `RESULTS.md`:
  ```sh
  julia --project=benchmark -t4 benchmark/characterize.jl cpu results/cpu-t4.json
  julia --project=benchmark/gpu/cuda benchmark/characterize.jl cuda results/gpu.json
  julia --project=benchmark benchmark/report.jl results/*.json
  ```
  `characterize.jl` overwrites the archive it is given, so measure into a new file and merge with
  `merge_parts.jl`, or replace one class with `replace_class.jl`. `characterize.sh` runs a host's
  lanes in one go, but hands `report.jl` only those lanes, so the other host's columns drop out of
  `RESULTS.md`.

After a sweep, compare it with the previous archive and explain every systematic change before
naming a cause; `report.jl` adds the born-slow triage and the history scan to `RESULTS.md` to
start from.

## Layout

- `benchmarks.jl` — `build_suite(; array_family, types, sizes)`, the suite every entry point builds.
- `harness.jl` — device-aware builders and `bench_sync`, which waits for the device before a timer
  stops.
- One file per class: `fft.jl`, `algebra.jl`, `operators.jl`, `convolution.jl`, `transfer.jl`,
  `reductions.jl`, `storage.jl` (device only), `resolution.jl`.
- `gate.jl`, `regress.jl`, `runbenchmarks.jl`, `characterize.jl`/`characterize.sh`, `report.jl`,
  `triage.jl`, `merge_parts.jl`, `replace_class.jl` — the runners above and their tools.
- `history_regressions.jl` — scans the committed history of `RESULTS.md` for cells slower than their
  best.
- `kernel_resources*.jl` — the compiled register and occupancy figures of the transfer kernels.
- `threading.jl`, `study_*.jl` — standalone studies.
- `gpu/<backend>/` — the per-backend environments and entry points.

A new public operation adds its benchmark to the matching class file; the coverage contract is in
`docs/PERFORMANCE.md` §5.
