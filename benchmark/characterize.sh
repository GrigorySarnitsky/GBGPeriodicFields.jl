#!/usr/bin/env bash
# Exhaustive characterization → benchmark/RESULTS.md. Sweeps the CPU thread count over powers of two
# (1 2 4 8) and runs one GPU, over each backend's default grids (CPU 64³–512³, device 64³–256³ —
# a device cannot hold 512³ in Float64) and all op-classes, then assembles a Markdown
# report. Raw JSON (benchmark/results/) is gitignored; RESULTS.md is the readable artifact. Takes
# ~15–30 min. See docs/PERFORMANCE.md §6.
#
#   bash benchmark/characterize.sh                                    # i7 / ROCm defaults (Aiporetne)
#   CPU_TAG=9800x3d GPU_BACKEND=cuda GPU_OUT=gpu-rtx5070ti.json \     # 9800X3D / CUDA box (Enteropia)
#     bash benchmark/characterize.sh
#
# Env knobs (defaults reproduce the original single-machine i7/ROCm run):
#   THREADS      thread set (default "1 2 4 8")
#   CPU_TAG      host-qualify the CPU json names → cpu-<TAG>-tN.json (default bare cpu-tN.json); lets one
#                report hold several CPUs (report.jl labels them "CPU <TAG> tN")
#   GPU_BACKEND  rocm (AMDGPU, default) or cuda (NVIDIA) — picks the benchmark/gpu/<backend> env
#   GPU_OUT      GPU json name (default gpu.json), e.g. gpu-rtx5070ti.json
# Per-lane overrides honored by characterize.jl (export here, or run it directly): CHAR_SIZES (grids,
# e.g. "64,128,256"), CHAR_TYPES ("Float64,Float32"), CHAR_SKIP (drop classes). E.g. a 512³ Float32
# GPU lane skipping the memory-heavy classes (see docs/PERFORMANCE.md §7):
#   CHAR_SIZES=512 CHAR_TYPES=Float32 CHAR_SKIP=transfer,reductions \
#     julia --project=benchmark/gpu/rocm benchmark/characterize.jl gpu benchmark/results/gpu-512.json
set -euo pipefail
cd "$(dirname "$0")/.."

THREADS="${THREADS:-1 2 4 8}"
CPU_TAG="${CPU_TAG:-}"
GPU_BACKEND="${GPU_BACKEND:-rocm}"
GPU_OUT="${GPU_OUT:-gpu.json}"
mkdir -p benchmark/results
cpu_jsons=()

cpu_suffix=""
if [ -n "$CPU_TAG" ]; then cpu_suffix="-$CPU_TAG"; fi
for t in $THREADS; do
  echo "=================== CPU${cpu_suffix} -t$t ==================="
  out="benchmark/results/cpu${cpu_suffix}-t$t.json"
  julia --project=benchmark -t"$t" benchmark/characterize.jl cpu "$out"
  cpu_jsons+=("$out")
done

# characterize.jl takes "gpu"/"rocm" (AMDGPU) or "cuda" (NVIDIA); the env lives under
# benchmark/gpu/<backend>. It builds one (size, element-type) at a time so 256³ fits in VRAM, and (AMD
# only) warms the code-object cache up front. NEVER kill a cold first GPU run (a killed compile never
# persists → the next run restarts cold). See PERFORMANCE.md §6.
case "$GPU_BACKEND" in
  cuda)     gpu_proj="benchmark/gpu/cuda"; gpu_arg="cuda" ;;
  rocm|gpu) gpu_proj="benchmark/gpu/rocm"; gpu_arg="gpu" ;;
  *) echo "unknown GPU_BACKEND=$GPU_BACKEND (want rocm|cuda)" >&2; exit 2 ;;
esac
gpu_json=()
echo "=================== GPU ($GPU_BACKEND) ==================="
if julia --project="$gpu_proj" benchmark/characterize.jl "$gpu_arg" "benchmark/results/$GPU_OUT"; then
  gpu_json=("benchmark/results/$GPU_OUT")
else
  echo "GPU run skipped/failed — report will omit the GPU column."
fi

julia --project=benchmark benchmark/report.jl "${cpu_jsons[@]}" "${gpu_json[@]}"
echo "done -> benchmark/RESULTS.md"
