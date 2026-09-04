# Dump a transfer kernel's compiled RESOURCE USAGE — registers, scratch (spills), occupancy — the
# numbers that settled PERFORMANCE.md finding (aq): decision 78's walk compiles `CatmullRom` on
# gfx1100 to 192 VGPRs with 292 B of scratch at 8 waves per EU, where the `mod` form gave 91 / 0 / 16,
# while `Lalescu(3,3)` is unchanged. Compile-only: it is NOT a measurement, needs no idle machine, and
# runs in seconds. Run it at two commits (a `git worktree` for the old one) and compare the lines.
#
#   julia --project=benchmark/gpu/rocm benchmark/kernel_resources.jl           # AMD, tested (gfx1100)
#   julia --project=benchmark/gpu/cuda benchmark/kernel_resources.jl           # NVIDIA, see below
#
# The AMD arm reads the compiler's resource comment block from the native dump. The CUDA arm dumps
# PTX (`CUDA.@device_code_ptx`) — PTX carries no final register count, so on that backend read the
# registers from the compiled kernel object (`CUDA.registers`) or from `cuobjdump
# --dump-resource-usage` on the cubin; the point of running it there is the falsification test in
# finding (aq): the sm_120 walk kernel should NOT cross a register tier for `CatmullRom`.
using GBGPeriodicFields
const USECUDA = Base.find_package("CUDA") !== nothing && !(Base.find_package("AMDGPU") !== nothing && get(ENV, "KR_BACKEND", "") == "rocm") && get(ENV, "KR_BACKEND", "cuda") == "cuda"
if USECUDA
  using CUDA; const AT = CuArray
else
  using AMDGPU; const AT = ROCArray
end
const N = 16
for (label, scheme) in (("CatmullRom", CatmullRom), ("Lalescu(3,3)", LalescuSpline(3, 3)))
  grid = Grid3D((N, N, N), (2π, 2π, 2π))
  f = ScalarFieldPhysical(AT(rand(Float64, N, N, N)), grid)
  pts = PointSet(AT(2π .* rand(Float64, 300, 3)))
  out = interpolate(f, pts, scheme)
  interpolate!(out, f, pts, scheme)
  buf = IOBuffer()
  if USECUDA
    CUDA.@device_code_ptx io=buf interpolate!(out, f, pts, scheme)
    txt = String(take!(buf))
    println(rpad(label, 14), " PTX dumped (", count(==('\n'), txt), " lines); read registers with CUDA.registers / cuobjdump --dump-resource-usage")
  else
    AMDGPU.GPUCompiler.@device_code_native io=buf interpolate!(out, f, pts, scheme)
    asm = String(take!(buf))
    pick(re) = (m = match(re, asm); m === nothing ? "?" : m.captures[1])
    cnt(re) = length(collect(eachmatch(re, asm)))
    println(rpad(label, 14), " NumVgprs=", pick(r"NumVgprs:\s*(\d+)"), " NumSgprs=", pick(r"NumSgprs:\s*(\d+)"),
            " ScratchSize=", pick(r"ScratchSize:\s*(\d+)"), " Occupancy=", pick(r"Occupancy:\s*(\d+)"),
            " scratch_ops=", cnt(r"scratch_(load|store)"), " instr≈", cnt(r"\n\s+[sv]_"))
  end
end
