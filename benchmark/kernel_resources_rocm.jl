# The AMD arm of kernel_resources.jl — tested on gfx1100. Reads the compiler's resource block from
# the native dump: VGPRs, SGPRs, scratch bytes (spills), waves per EU, and counts scratch operations
# and instructions in the emitted code.
using AMDGPU
const AT = ROCArray
function dump_resources(label, call)
  buf = IOBuffer()
  AMDGPU.GPUCompiler.@device_code_native io=buf call()
  asm = String(take!(buf))
  pick(re) = (m = match(re, asm); m === nothing ? "?" : m.captures[1])
  cnt(re) = length(collect(eachmatch(re, asm)))
  println(rpad(label, 14), " NumVgprs=", pick(r"NumVgprs:\s*(\d+)"), " NumSgprs=", pick(r"NumSgprs:\s*(\d+)"),
          " ScratchSize=", pick(r"ScratchSize:\s*(\d+)"), " Occupancy=", pick(r"Occupancy:\s*(\d+)"),
          " scratch_ops=", cnt(r"scratch_(load|store)"), " instr≈", cnt(r"\n\s+[sv]_"))
end
