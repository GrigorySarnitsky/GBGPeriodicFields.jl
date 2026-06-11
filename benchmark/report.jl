# Assemble characterization JSONs (benchmark/characterize.jl output) into the committed Markdown
# report benchmark/RESULTS.md: one table per op-class, rows = operation × element-type × grid,
# columns = the backend/thread-count of each input file (derived from its name). Minimum time.
#
#   julia --project=benchmark benchmark/report.jl results/cpu-t1.json … results/gpu.json
#
# Driven by benchmark/characterize.sh. See docs/PERFORMANCE.md §6.

using BenchmarkTools
using Dates

const CLASSES = ("fft", "algebra", "operators", "transfer", "reductions")

# cpu-t1.json → "CPU t1", gpu.json → "GPU"
label_of(path) = (b = splitext(basename(path))[1]; b == "gpu" ? "GPU" : replace(b, "cpu-t" => "CPU t"))

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
println(io, "Minimum time per operation; `—` = not measured for that column. Generated ",
        Dates.format(now(), "yyyy-mm-dd"), " at commit `", commit, "` on Julia ", VERSION,
        ", host `", gethostname(), "`. Columns below are the runs supplied; grids and element types ",
        "are in the row labels. The **CPU thread sweep 1/2/4/8 and the GPU (RX 6700 XT, gfx1031, ROCm) ",
        "all cover 64³–256³, every op-class incl. FFT — except the GPU `reductions` column, pending a ",
        "device-reset re-run.** The GPU sweep builds one (grid, element-type) ",
        "at a time so 256³ fits in 12 GB VRAM (PERFORMANCE.md §6 gap 5). **Regenerate** with ",
        "`benchmark/characterize.sh`. ~10% jitter.\n")

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
