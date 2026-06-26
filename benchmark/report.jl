# Assemble characterization JSONs (benchmark/characterize.jl output) into the committed Markdown
# report benchmark/RESULTS.md: one table per op-class, rows = operation × element-type × grid,
# columns = the backend/thread-count of each input file (derived from its name). Minimum time.
#
#   julia --project=benchmark benchmark/report.jl results/cpu-t1.json … results/gpu.json
#
# Driven by benchmark/characterize.sh. See docs/PERFORMANCE.md §6.

using BenchmarkTools
using Dates

const CLASSES = ("fft", "algebra", "operators", "convolution", "transfer", "reductions")

# cpu-t1.json → "CPU t1"; gpu-rx7900xtx.json → "GPU 7900XTX"; gpu-gtx1070.json → "GPU 1070";
# a bare gpu.json / cuda.json → "GPU". The per-card suffix lets one report hold several devices.
function label_of(path)
  b = splitext(basename(path))[1]
  startswith(b, "cpu-t") && return replace(b, "cpu-t" => "CPU t")
  b in ("gpu", "cuda") && return "GPU"
  startswith(b, "gpu-") && return "GPU " * uppercase(replace(b, "gpu-" => "", "rx" => "", "gtx" => ""))
  return b
end

cell(group, class, key) = (haskey(group, class) && haskey(group[class], key)) ?
  BenchmarkTools.prettytime(time(minimum(group[class][key]))) : "—"

classkeys(group, class) = haskey(group, class) ? collect(keys(group[class])) : String[]

paths  = ARGS
groups = [(label_of(p), BenchmarkTools.load(p)[1]) for p in paths]
labels = first.(groups)

commit = try
  readchomp(`git rev-parse --short HEAD`)
catch
  "unknown"
end

io = IOBuffer()
println(io, "# Benchmark results\n")
println(io, "Minimum time per operation; `—` = not measured for that column (a device / grid / ",
        "element-type combination not run). Generated ",
        Dates.format(now(), "yyyy-mm-dd"), " at commit `", commit, "` on Julia ", VERSION,
        ", host `", gethostname(), "`. Columns are the supplied runs; grids and element types are ",
        "in the row labels. **CPU** = i7-12700K thread sweep 1/2/4/8 (host `Aiporetne`). **GPUs**, ",
        "newest last: **GTX 1070** (Pascal, CUDA, 8 GB — `Enteropia`, a *separate* office host, 64³/128³ only); ",
        "**RX 6700 XT** (gfx1031, ROCm, 12 GB — `Aiporetne`, 64³–256³); **RX 7900 XTX** (gfx1100, ",
        "ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the ",
        "`transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ ",
        "and the radial diagnostics' working set hits the 24 GB ceiling). The GPU sweep builds ",
        "one (op-class, grid, element-type) at a time so the working set stays bounded ",
        "(PERFORMANCE.md §7). **Regenerate** with `benchmark/characterize.sh` plus the per-card ",
        "archive in `benchmark/results/` (PERFORMANCE.md §6). ~10% jitter.\n")

for class in CLASSES
  println(io, "## ", class, "\n")
  allkeys = sort(unique(reduce(vcat, [classkeys(g, class) for (_, g) in groups]; init = String[])))
  println(io, "| operation | ", join(labels, " | "), " |")
  println(io, "|", repeat(":--|", length(labels) + 1))
  for key in allkeys
    println(io, "| ", key, " | ", join((cell(g, class, key) for (_, g) in groups), " | "), " |")
  end
  println(io)
end

open(joinpath(@__DIR__, "RESULTS.md"), "w") do f
  write(f, String(take!(io)))
end
println("wrote benchmark/RESULTS.md  (", length(paths), " input files: ", join(labels, ", "), ")")
