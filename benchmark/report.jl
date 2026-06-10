# Assemble characterization JSONs (benchmark/characterize.jl output) into the committed Markdown
# report benchmark/RESULTS.md: one table per op-class, rows = operation × element-type × grid,
# columns = the backend/thread-count of each input file (derived from its name). Minimum time.
#
#   julia --project=benchmark benchmark/report.jl results/cpu-t1.json … results/gpu.json
#
# Driven by benchmark/characterize.sh. See docs/PERFORMANCE.md §6.

using BenchmarkTools
using Dates

const CLASSES = ("fft", "algebra", "operators", "transfer")

# cpu-t1.json → "CPU t1", gpu.json → "GPU"
label_of(path) = (b = splitext(basename(path))[1]; b == "gpu" ? "GPU" : replace(b, "cpu-t" => "CPU t"))

cell(group, class, key) = haskey(group[class], key) ?
  BenchmarkTools.prettytime(time(minimum(group[class][key]))) : "—"

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
        "are in the row labels. The **CPU thread sweep 1/2/4/8 covers 64³–256³**. The **GPU column is ",
        "omitted here**: GPU FFT is unstable under AMDGPU/rocFFT on this gfx1030 (256³ plan creation ",
        "stalls host-side and can wedge the device — PERFORMANCE.md §6 gap 5); current GPU numbers are ",
        "in PERFORMANCE.md §4/§6. **Regenerate** with `benchmark/characterize.sh`. ~10% jitter.\n")

for class in CLASSES
  println(io, "## ", class, "\n")
  allkeys = sort(unique(reduce(vcat, [collect(keys(g[class])) for (_, g) in groups]; init = String[])))
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
