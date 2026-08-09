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
        "**Both GPU columns are now in the fixed measurement regime and are comparable again.** Device lanes used to run with a blanket `gcsample = true`, so a full `GC.gc()` — whose finalizers free device buffers and synchronize — preceded every sample and dominated operations lasting tens of microseconds, inflating device rows 18.4–29.2× at ``64^3``, 5.8–19.8× at ``128^3`` and 1.9–4.25× at ``256^3`` on the AMD card. `gcsample` is now decided per row from a measured device-pool probe and kept only for rows that genuinely materialize. **GPU 7900XTX was re-swept 2026-08-07** (median −81.6%) and **GPU 5070TI on 2026-08-09** (median −46.4% over 426 rows). The NVIDIA correction is the smaller of the two because that vendor's collect-and-synchronize is cheaper, not because less was wrong: the CUDA branch of the probe called `CUDA.available_memory`, which is not a binding, so it threw on every row and the catch-all held every CUDA row on the collector until 2026-08-09 — see PERFORMANCE.md §4(w), and note that a fallback reported as a measurement is the reason that went unnoticed. CPU columns were never affected, `gcsample` being gated on the backend. See PERFORMANCE.md §4(s). ",
        "**`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and at the larger grids the shift does not reproduce:** across that host's 192 `fft` rows (four lanes × 48) against its 2026-07-22 archive, exactly **one** row at ``256^3`` moved slower and by +1.0%, where `Enteropia` moved +38%; per-lane medians run −4.5% to −6.8%. Twenty-three rows did move slower, but all except that one sit at ``64^3``/``128^3``, and the three exceeding 20% are small-grid high-thread-count cells where thread overhead dominates a sub-millisecond workload. This host's rows moved materially *faster* at the larger grids (up to a ratio of 0.54), which is no better explained, so a cross-vintage `fft` comparison is uninformative rather than evidence. `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. **The 2026-08-09 `Enteropia` re-sweep settles it: the shift was a ONE-OFF, not a persistent state change.** Re-measuring t1/t2/t4 against the 2026-08-05 archive over an interval with no source changes, the `fft` class is flat — per-lane medians −1.1% to −1.4%, and at ``256^3`` specifically −3.7%, −6.5% and −1.2%, where the event being explained was +20–50%. Every other class is flat too (600 rows per lane, overall medians +0.0%, −0.2%, −0.2%), so the sweep reproduces itself and the instrument is sound. Those three lanes are also the first archives carrying stamped platform state (kernel, microcode, governor, SMT, transparent huge pages), so a recurrence is now falsifiable instead of unattributable. See PERFORMANCE.md §4(p). ",
        "**The `CPU 9800X3D t8` column is one vintage behind its three siblings, and cannot currently be advanced.** The 2026-08-09 re-sweep completed t1, t2 and t4 and then failed the t8 lane **three times consecutively** with `signal 11` inside `spawn_apply` in `libfftw3`, reached through FFTW.jl's `spawnloop` — the fault of PERFORMANCE.md §4(q), which is host-specific to `Enteropia` and is now reproducible there rather than a one-off. Nothing is corrupted: `characterize.jl` writes its JSON only at the end, so that column is intact at its 2026-08-05 vintage. Comparing t1→t8 thread scaling on this host therefore crosses vintages — which is materially safe here, because the three lanes that *were* re-measured came back flat against 2026-08-05 (overall medians +0.0%, −0.2%, −0.2% over 600 rows each), so the vintages agree to within noise. ",
        "A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field. Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. ",
        "The GPU sweep builds one (op-class, grid, element-type) at a time so ",
        "the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes ",
        "you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand ",
        "over **every** archive in `benchmark/results/`, this table's own column list included. Do ",
        "not use `characterize.sh` for a multi-host report: it passes only the lanes it just ",
        "produced to `report.jl`, so the columns belonging to the other host and to retired cards ",
        "would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was ",
        "measured at, stamped into its JSON by `characterize.jl`: ", join(vintage_parts, "; "),
        ". **Jitter is ~10% for most cells but NOT uniform: it reaches 1.44x at small grids under high thread counts.** Measured on the 12700K, `mean(norm) vec` `Float32`, five repeats of the same measurement: at ``64^3`` `-t8` the minimum came out 31.2, 31.0, 31.3, 30.8 and 44.4 us, where the same row at `-t1` spans 1.01x and at ``256^3`` `-t8` spans 1.09x. The work there (~31 us) is comparable to the cost of spawning eight threads, and taking BenchmarkTools' minimum over a one-second budget does not suppress it. So a movement of tens of percent in a small-grid, high-thread cell is NOT evidence of anything; compare those at ``256^3`` or above, or at low thread counts. PERFORMANCE.md §4(u).\n")

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
