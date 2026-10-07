# Dump a transfer kernel's compiled RESOURCE USAGE — registers, scratch (spills), occupancy — the
# numbers that settled PERFORMANCE.md finding (aq): decision 78's walk compiles `CatmullRom` on
# gfx1100 to 192 VGPRs with 292 B of scratch at 8 waves per EU, where the `mod` form gave 91 / 0 / 16,
# while `Lalescu(3,3)` is unchanged. Compile-only: it is NOT a measurement, needs no idle machine, and
# runs in seconds. Run it at two commits (a `git worktree` for the old one) and compare the lines.
#
#   julia --project=benchmark/gpu/rocm benchmark/kernel_resources.jl           # AMD, tested (gfx1100)
#   julia --project=benchmark/gpu/cuda benchmark/kernel_resources.jl           # NVIDIA, tested (sm_120)
#
# The AMD arm reads the compiler's resource comment block from the native dump. The CUDA arm hands
# each kernel's PTX to NVIDIA's `ptxas -v` in compile-only mode and reads registers, stack and spills
# from its report. On 2026-10-04 it ran finding (aq)'s falsification test: on sm_120 the walk takes
# `CatmullRom` from 90 registers to 80, crossing no register tier.
using GBGPeriodicFields, Pkg
# One file per backend, `include`d at run time: a macro from a module that is not loaded fails at
# EXPANSION, and a top-level `if` is lowered as one expression, so a branch cannot hide the other
# backend's macro — only a separate file can. The backend is the one the ACTIVE project declares.
const BACKEND = haskey(Pkg.project().dependencies, "CUDA") ? "cuda" : "rocm"
include(joinpath(@__DIR__, "kernel_resources_$(BACKEND).jl"))   # defines AT and dump_resources
const N = 16
for (label, scheme) in (("CatmullRom", CatmullRom), ("Lalescu(3,3)", LalescuSpline(8; smoothness = 3)))
  grid = Grid3D((N, N, N), (2π, 2π, 2π))
  f = ScalarFieldPhysical(AT(rand(Float64, N, N, N)), grid)
  pts = PointSet(AT(2π .* rand(Float64, 300, 3)))
  out = ScalarPointValues(AT(zeros(Float64, 300)))
  # The dump wraps the kernel's FIRST call: CUDA's PTX is captured at compilation, and the AMD dump
  # reads the same compilation's resource block.
  dump_resources(label, () -> interpolate!(out, f, pts, scheme))
end
