#!/usr/bin/env bash
# Exhaustive characterization → benchmark/RESULTS.md. Sweeps the CPU thread count over powers of two
# (1 2 4 8 — the i7-12700K's performance cores) and runs the ROCm GPU, each over grids 64³–256³ and
# all op-classes, then assembles a committed Markdown report. Raw JSON (benchmark/results/) is
# gitignored; RESULTS.md is the readable artifact. Takes ~15–30 min. See docs/PERFORMANCE.md §6.
#
#   bash benchmark/characterize.sh
#
# Override the thread set:  THREADS="1 2 4 8 16" bash benchmark/characterize.sh
# Per-lane overrides honored by characterize.jl (export here, or run that script directly): CHAR_SIZES
# (grids, e.g. "64,128,256"), CHAR_TYPES ("Float64,Float32"), CHAR_SKIP (drop classes). E.g. a 512³
# Float32 GPU lane skipping the memory-heavy classes (see docs/PERFORMANCE.md §7):
#   CHAR_SIZES=512 CHAR_TYPES=Float32 CHAR_SKIP=transfer,reductions \
#     julia --project=benchmark/gpu/rocm benchmark/characterize.jl gpu benchmark/results/gpu-512.json
set -euo pipefail
cd "$(dirname "$0")/.."

THREADS="${THREADS:-1 2 4 8}"
mkdir -p benchmark/results
cpu_jsons=()

for t in $THREADS; do
  echo "=================== CPU -t$t ==================="
  julia --project=benchmark -t"$t" benchmark/characterize.jl cpu "benchmark/results/cpu-t$t.json"
  cpu_jsons+=("benchmark/results/cpu-t$t.json")
done

gpu_json=()
echo "=================== GPU (ROCm) ==================="
# Full GPU sweep, all classes incl. FFT, 64³–256³. characterize.jl builds one (size, element-type)
# at a time so 256³ fits in 12 GB VRAM, and warms the code-object cache up front. NEVER kill a cold
# first GPU run (a killed compile never persists → the next run restarts cold). See PERFORMANCE.md §6.
if julia --project=benchmark/gpu/rocm benchmark/characterize.jl gpu benchmark/results/gpu.json; then
  gpu_json=("benchmark/results/gpu.json")
else
  echo "GPU run skipped/failed — report will omit the GPU column."
fi

julia --project=benchmark benchmark/report.jl "${cpu_jsons[@]}" "${gpu_json[@]}"
echo "done -> benchmark/RESULTS.md"
