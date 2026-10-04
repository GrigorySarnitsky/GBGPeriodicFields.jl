# The NVIDIA arm of kernel_resources.jl, first run on the RTX 5070 Ti (sm_120) on 2026-10-04.
#
# PTX carries no final register count, and the PTX a call emits cannot be loaded on its own (it
# calls CUDA.jl's runtime, `gpu_report_exception`, which is linked in at compilation). So each
# kernel's PTX is handed to NVIDIA's own `ptxas` in compile-only mode, where an unresolved external
# is no error, and `-v` reports what the compiled kernel uses: registers per thread, the stack frame,
# and the spill stores and loads.
#
# The occupancy printed is the REGISTER limit alone: warps per multiprocessor that the register file
# allows, at the 256-register allocation granularity per warp, from the device's own register file
# and thread limit. It is the quantity finding (aq) is about — whether a register tier is crossed —
# and not the achieved occupancy, which the block size and other limits also set.
using CUDA, CUDA_Compiler_jll
const AT = CuArray

function _register_limited_warps(registers)
  device = CUDA.device()
  register_file = CUDA.attribute(device, CUDA.DEVICE_ATTRIBUTE_MAX_REGISTERS_PER_MULTIPROCESSOR)
  max_warps = CUDA.attribute(device, CUDA.DEVICE_ATTRIBUTE_MAX_THREADS_PER_MULTIPROCESSOR) ÷ 32
  per_warp = cld(registers * 32, 256) * 256
  return min(max_warps, register_file ÷ per_warp), max_warps
end

# `call` must be the FIRST call of its kernel in this process: the PTX is captured at compilation.
function dump_resources(label, call)
  buffer = IOBuffer()
  CUDA.@device_code_ptx io=buffer call()
  ptx = String(take!(buffer))
  for chunk in split(ptx, r"(?=^// PTX CompilerJob)"m; keepempty = false)
    entry = match(r"\.(?:visible\s+)?entry\s+(\w+)", chunk)
    entry === nothing && continue
    occursin("interpolate", entry.captures[1]) || continue
    # The architecture is the PTX's own target, `sm_120a` here: CUDA.jl compiles for the
    # architecture-specific variant, and `ptxas` refuses to lower it for the plain `sm_120`.
    target = match(r"\.target\s+(\w+)", chunk)
    architecture = target === nothing ? "?" : target.captures[1]
    source = tempname() * ".ptx"
    write(source, chunk[findfirst(".version", chunk)[1]:end])
    captured = IOBuffer()      # `ptxas -v` writes its report to stderr
    run(pipeline(`$(CUDA_Compiler_jll.ptxas()) -arch=$(architecture) -c -v $(source) -o $(tempname())`;
                 stdout = captured, stderr = captured))
    report = String(take!(captured))
    pick(pattern) = (m = match(pattern, report); m === nothing ? "?" : m.captures[1])
    registers = pick(r"Used (\d+) registers")
    warps, max_warps = registers == "?" ? ("?", "?") : _register_limited_warps(parse(Int, registers))
    println(rpad(label, 14), " ", architecture,
            "  registers ", lpad(registers, 3),
            "  stack ", lpad(pick(r"(\d+) bytes stack frame"), 4), " B",
            "  spill stores ", lpad(pick(r"(\d+) bytes spill stores"), 4), " B",
            "  spill loads ", lpad(pick(r"(\d+) bytes spill loads"), 4), " B",
            "  register-limited occupancy ", warps, "/", max_warps, " warps")
  end
end
