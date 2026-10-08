# Examples

A forced homogeneous isotropic turbulence simulation built on **GBGPeriodicFields**, in three versions
that run the same solver:

- `HIST_CPU.jl` — on the CPU, in `Float64`.
- `gpu/cuda/HIST_CUDA.jl` — on an NVIDIA GPU, in `Float32`.
- `gpu/rocm/HIST_ROCm.jl` — on an AMD GPU, in `Float32`.

The method, and how to read the plots, are on the documentation's
[Examples page](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/examples/hist_cpu/).

## Running

Each version has its own environment. From the root of a clone of the repository:

```sh
julia --project=examples -e 'using Pkg; Pkg.instantiate()'
julia --project=examples examples/HIST_CPU.jl --smoke

julia --project=examples/gpu/cuda -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/gpu/cuda examples/gpu/cuda/HIST_CUDA.jl --smoke

julia --project=examples/gpu/rocm -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke
```

The flag chooses the configuration:

- no flag — 32³, about a minute on the CPU;
- `--smoke` — a few seconds, to check that everything runs;
- `--fast` — 64³;
- `--huge` — 192³;
- `--mega` — 256³;
- `--giant` — 320³, the GPU versions only.

The largest configurations take hours on the CPU; pass `-t8` (or another thread count) to Julia to use
more CPU threads. The figures need a LaTeX installation.

## Output

Each run writes its data and figures to the `output/` folder beside its script, named after the
version and the configuration, so a quick run never overwrites a long one: `HIST_CUDA_giant.h5` for
the data, and `HIST_CUDA_giant_spectrum.png` and its siblings for the figures. The figures can be
redrawn from the data without running the simulation again:

```sh
julia --project=examples examples/plot_hist.jl examples/gpu/cuda/output/HIST_CUDA_giant.h5
```

The figures on the documentation's Examples page, and the data they were drawn from
(`HIST_CUDA_giant.h5`), are in `figures/`.
