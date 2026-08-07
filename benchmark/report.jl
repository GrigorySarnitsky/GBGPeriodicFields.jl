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

# cpu-t1.json → "CPU t1"; cpu-9800x3d-t4.json → "CPU 9800X3D t4"; gpu-rx7900xtx.json → "GPU 7900XTX";
# gpu-gtx1070.json → "GPU 1070"; gpu-rtx5070ti.json → "GPU 5070TI"; a bare gpu.json / cuda.json → "GPU".
# The per-host CPU segment and the per-card GPU suffix let one report hold several CPUs and GPUs.
function label_of(path)
  b = splitext(basename(path))[1]
  startswith(b, "cpu-t") && return replace(b, "cpu-t" => "CPU t")        # bare cpu-tN (host in prose)
  # host-qualified CPU, e.g. cpu-9800x3d-t4 → "CPU 9800X3D t4"
  (m = match(r"^cpu-(.+)-t(\d+)$", b)) !== nothing &&
    return "CPU " * uppercase(m.captures[1]) * " t" * m.captures[2]
  b in ("gpu", "cuda") && return "GPU"
  # strip the vendor tag (rtx before rx so "rtx…" is not half-eaten): gpu-rtx5070ti → "GPU 5070TI"
  startswith(b, "gpu-") &&
    return "GPU " * uppercase(replace(b, "gpu-" => "", "rtx" => "", "rx" => "", "gtx" => ""))
  return b
end

cell(group, class, key) = (haskey(group, class) && haskey(group[class], key)) ?
  BenchmarkTools.prettytime(time(minimum(group[class][key]))) : "—"

classkeys(group, class) = haskey(group, class) ? collect(keys(group[class])) : String[]

paths  = ARGS
groups = [(label_of(p), BenchmarkTools.load(p)[1]) for p in paths]
labels = first.(groups)

# Each archive may carry vintage tags stamped by characterize.jl ("commit=…", "measured=…"); a
# column from an unstamped (older) archive falls back to the header prose for its vintage. This
# line is what keeps a stale column from silently claiming the report's HEAD feature state.
function vintage_of(group)
  tag_value(prefix) = begin
    i = findfirst(t -> t isa AbstractString && startswith(t, prefix), group.tags)
    i === nothing ? nothing : String(group.tags[i])[(length(prefix) + 1):end]
  end
  commit = tag_value("commit=")
  commit === nothing && return nothing
  measured = tag_value("measured=")
  return measured === nothing ? commit : "$(commit) @ $(measured)"
end

vintages = Dict{Union{String, Nothing}, Vector{String}}()
for (label, group) in groups
  push!(get!(vintages, vintage_of(group), String[]), label)
end
vintage_parts = String[]
for key in sort(collect(keys(vintages)); by = k -> something(k, "￿"))
  columns = join(vintages[key], ", ")
  push!(vintage_parts, key === nothing ? "unstamped (vintage in the prose above): " * columns :
                                         "`" * key * "`: " * columns)
end

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
        ", assembled on host `", gethostname(), "` — a **multi-host** report (each device names its ",
        "own host below). Columns are the supplied runs; grids and element types are in the row ",
        "labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–**512³** both element types) and ",
        "**Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** ",
        "both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds ",
        "nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded ",
        "assignments and the fused one-pass kernels, so thread scaling is monotone (the retired ",
        "inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns ",
        "now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically ",
        "with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the ",
        "reductions cells are cross-host comparable. **GPUs**, ",
        "newest last: **RX 7900 XTX** ",
        "(gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, ",
        "the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to ",
        "1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** ",
        "(Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the ",
        "`mul!` tensor field alone is 4.5 GB). **The two retired cards were DROPPED on 2026-08-07** — ",
        "a GTX 1070 (`Enteropia`, pre-swap) and an RX 6700 XT (`Aiporetne`, pre-swap) each held a ",
        "column here for the record. Both were measured under the `gcsample` regime of PERFORMANCE.md ",
        "§4(s), which inflated device rows 2–29×, and neither card exists any more, so those columns ",
        "could never be re-swept and were permanently un-comparable against anything measured after ",
        "the fix. A column that cannot be corrected and cannot be compared is worse than absent, ",
        "because it invites exactly the comparison it cannot support. Each office box was upgraded in ",
        "place: `Enteropia` GTX 1070 → RTX 5070 Ti (both CUDA), `Aiporetne` RX 6700 XT → RX 7900 XTX ",
        "(both ROCm). Every remaining column is measured at the decision-38/39 rewrite. ",
        "**EVERY GPU COLUMN BELOW IS INFLATED 2–29× BY THE HARNESS AND DOES NOT MEASURE THE OPERATION (2026-08-07).** Device lanes run with `gcsample = true`, so a full `GC.gc()` — whose finalizers free device buffers and synchronize — precedes every sample and dominates operations that take tens of microseconds. Measured A/B on the RX 7900 XTX with only that parameter changed: 18.4–29.2× at ``64^3``, 5.8–19.8× at ``128^3``, and still 1.9–4.25× at ``256^3``. The tell is visible in the table itself — `convolve! scalar` and `convolve! vector` at ``128^3`` read 1.094 and 1.177 ms, a 3× difference in bytes moved showing as 1.08×, where the true values are 57 and 182 µs. The inflation is NOT a uniform factor, so it also distorts row-to-row comparisons within a GPU column, and at least one conclusion reverses without it (the radial kernel class is faster than the stored one, not slower). CPU columns are unaffected — `gcsample` is gated on the backend. **The harness is now fixed** (`gcsample` is decided per row from a measured device-pool probe, keeping it only for rows that genuinely materialize), **but the columns below were measured before that fix and have not been re-swept.** Treat every GPU cell as an upper bound of unknown tightness, and do not compare one against a freshly measured value; see PERFORMANCE.md §4(s). ",
        "**`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and at the larger grids the shift does not reproduce:** across that host's 192 `fft` rows (four lanes × 48) against its 2026-07-22 archive, exactly **one** row at ``256^3`` moved slower and by +1.0%, where `Enteropia` moved +38%; per-lane medians run −4.5% to −6.8%. Twenty-three rows did move slower, but all except that one sit at ``64^3``/``128^3``, and the three exceeding 20% are small-grid high-thread-count cells where thread overhead dominates a sub-millisecond workload. This host's rows moved materially *faster* at the larger grids (up to a ratio of 0.54), which is no better explained, so a cross-vintage `fft` comparison is uninformative rather than evidence. `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. See PERFORMANCE.md §4(p). ",
        "A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field. Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. ",
        "The GPU sweep builds one (op-class, grid, element-type) at a time so ",
        "the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes ",
        "you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand ",
        "over **every** archive in `benchmark/results/`, this table's own column list included. Do ",
        "not use `characterize.sh` for a multi-host report: it passes only the lanes it just ",
        "produced to `report.jl`, so the columns belonging to the other host and to retired cards ",
        "would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was ",
        "measured at, stamped into its JSON by `characterize.jl`: ", join(vintage_parts, "; "),
        ". ~10% jitter.\n")

for class in CLASSES
  println(io, "## ", class, "\n")
  allkeys = sort(unique(reduce(vcat, [classkeys(g, class) for (_, g) in groups]; init = String[])))
  # A benchmark key is "<operation> | <workload>", so a data row below carries TWO label cells
  # before the timings. The header must declare both: while it named only `operation` every table
  # had one more data column than it declared, and a Markdown renderer resolves that by dropping
  # the overflow — so the last backend column silently vanished from the rendered page even though
  # the committed text held it.
  println(io, "| operation | workload | ", join(labels, " | "), " |")
  println(io, "|", repeat(":--|", length(labels) + 2))
  for key in allkeys
    println(io, "| ", key, " | ", join((cell(g, class, key) for (_, g) in groups), " | "), " |")
  end
  println(io)
end

open(joinpath(@__DIR__, "RESULTS.md"), "w") do f
  write(f, String(take!(io)))
end
println("wrote benchmark/RESULTS.md  (", length(paths), " input files: ", join(labels, ", "), ")")
