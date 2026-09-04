# The NVIDIA arm of kernel_resources.jl — NOT yet run on a CUDA host (written on Aiporetne, which has
# none). PTX carries no final register count, so this arm dumps the PTX for the record and prints
# where the number actually lives; the office session that runs it should replace the println with
# `CUDA.registers` on the compiled kernel or `cuobjdump --dump-resource-usage` on the cubin, and
# then delete this caveat.
using CUDA
const AT = CuArray
function dump_resources(label, call)
  buf = IOBuffer()
  CUDA.@device_code_ptx io=buf call()
  txt = String(take!(buf))
  println(rpad(label, 14), " PTX dumped (", count(==('\n'), txt),
          " lines); read registers with CUDA.registers / cuobjdump --dump-resource-usage")
end
