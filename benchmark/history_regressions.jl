# Did we ship anything SLOWER? A regression hunt over the committed history of RESULTS.md.
#
#     julia benchmark/history_regressions.jl [threshold]      # default 1.25
#
# Not a prose audit: this reads the measured table at every commit that regenerated it and looks for
# (row, column) cells that are materially slower at HEAD than they were earlier, persistently.
#
# It exists because every other layer answers a different question. The canary is a fixed sample of
# mechanisms, the born-slow triage asks whether an operation threads and whether it matches its peers,
# and a sweep's own write-up compares one archive against one predecessor, so a slow drift, or a step
# in a row nobody was watching, is invisible to all three. This reads the whole committed history of
# every cell at once. Its first run found finding (am): a 1.45-1.48x regression in the width-8 CPU
# scatter that had been shipped for two days, sitting in a table that three instruments had passed.
#
# A cell flagged here is a HYPOTHESIS. Confirm it with a matched A/B against the commit before the
# step (the step's date names it), both arms reproducing their own archives, before calling it real:
# this table mixes hosts, sweep shapes and measurement regimes, and several documented effects
# (finding (y) process history, section 4(u) jitter, finding (ak)'s stale visit order) move rows
# without any code changing.
#
# Measurement-regime boundaries are respected, because ignoring them produces nonsense:
#   - DEVICE columns are only comparable from the gcsample repair onward (AMD 2026-08-07 db7e6dd8,
#     CUDA 2026-08-09 d5f6814a); before it every device row timed the collector (finding (s)).
#   - CPU columns were never affected by gcsample, but the decision-38/39 threading rewrite
#     (2026-07-22) reshaped them, so that is their floor.
# A cell is only compared against readings inside its own regime.
#
# Base Julia only, so `report.jl` can run it from any environment. It replaced a Python script of the
# same name on 2026-10-20, and its output was checked identical to that script's before it went.

# Derived from this file's own location, not hardcoded: `report.jl` invokes the script from whatever
# directory a sweep happens to run in, and the fleet's two hosts need not agree on an absolute path. A
# wrong root here would not error — `git show` would simply find nothing, and the scan would report a
# clean history it never read.
const REPOSITORY = dirname(@__DIR__)

git(arguments...) = read(Cmd(`git $arguments`; dir = REPOSITORY), String)

const UNIT_IN_MILLISECONDS = Dict("s" => 1000.0, "ms" => 1.0, "μs" => 1e-3, "us" => 1e-3)

table_cells(line) = [strip(cell) for cell in split(strip(strip(line), '|'), '|')]

"""(operation, workload, column) => milliseconds, from one RESULTS.md, in the table's own order."""
function parse_results(text)
  out = Pair{NTuple{3, String}, Float64}[]
  header = nothing
  for line in split(text, '\n')
    if startswith(line, "| operation")
      header = table_cells(line)
      continue
    end
    (startswith(line, "|") && header !== nothing) || continue
    cells = table_cells(line)
    (length(cells) == length(header) && !startswith(cells[1], "---")) || continue
    for (column, cell) in zip(header[3:end], cells[3:end])
      m = match(r"^([\d.]+)\s*(ms|μs|us|s)$", cell)
      m === nothing && continue
      push!(out, (String(cells[1]), String(cells[2]), String(column)) =>
                 parse(Float64, m.captures[1]) * UNIT_IN_MILLISECONDS[m.captures[2]])
    end
  end
  return out
end

function median(values)
  sorted = sort(values); n = length(sorted)
  return isodd(n) ? sorted[(n + 1) ÷ 2] : (sorted[n ÷ 2] + sorted[n ÷ 2 + 1]) / 2
end

# Python's fixed-point and left-justified field formats, which the output was checked against.
fixed(x, digits) = Base.Ryu.writefixed(x, digits)
leftfield(text, width) = (t = first(text, width); t * " "^(width - length(t)))
rightfield(text, width) = " "^max(0, width - length(text)) * text

const CPU_FLOOR, AMD_FLOOR, NVIDIA_FLOOR = "2026-07-22", "2026-08-07", "2026-08-09"
floor_for(column) = startswith(column, "CPU") ? CPU_FLOOR :
                    (occursin("7900", column) || occursin("6700", column)) ? AMD_FLOOR : NVIDIA_FLOOR

function main(arguments)
  commits = Tuple{String, String}[]
  for line in split(git("log", "--format=%h %ad", "--date=short", "--reverse", "--",
                        "benchmark/RESULTS.md"), '\n'; keepempty = false)
    hash, date = split(line)
    push!(commits, (String(hash), String(date)))
  end

  # Insertion order kept, as the scan reports ties and groups in the order cells were first seen.
  keys_in_order = NTuple{3, String}[]
  series = Dict{NTuple{3, String}, Vector{Tuple{String, String, Float64}}}()   # key => [(date, commit, ms)]
  for (hash, date) in commits
    for (key, value) in parse_results(git("show", "$hash:benchmark/RESULTS.md"))
      date >= floor_for(key[3]) || continue
      haskey(series, key) || (push!(keys_in_order, key); series[key] = [])
      push!(series[key], (date, hash, value))
    end
  end
  println("parsed $(length(commits)) versions of RESULTS.md; $(length(series)) (row, column) cells in-regime\n")

  threshold = isempty(arguments) ? 1.25 : parse(Float64, arguments[1])
  findings = NamedTuple[]
  for key in keys_in_order
    history = series[key]
    length(history) < 2 && continue
    operation, workload, column = key
    current_date, _, current = history[end]
    best, best_date, _ = minimum((value, date, hash) for (date, hash, value) in history[1:end-1])
    current / best >= threshold || continue
    # Persistence: is HEAD's regime the tail, or is the old best a one-off dip?
    tail = [value for (_, _, value) in history[max(1, end - 2):end]]
    earlier = [value for (_, _, value) in history[1:max(0, end - 3)]]
    isempty(earlier) && (earlier = [best])
    push!(findings, (; operation, workload, column, ratio = current / best, best, best_date,
                       current, current_date, n = length(history),
                       tail_median = median(tail), earlier_median = median(earlier)))
  end

  sort!(findings; by = f -> -f.ratio)
  println("=== cells at least $(fixed(threshold, 2))x slower at HEAD than their in-regime best: $(length(findings))\n")
  for f in first(findings, 45)
    persistent = f.tail_median / f.earlier_median >= 1.15 ? "PERSISTENT" : "one-off?"
    println(rightfield(fixed(f.ratio, 2), 6), "x  ", leftfield(f.operation, 34), " ",
            leftfield(f.workload, 16), " ", leftfield(f.column, 15), " ",
            rightfield(fixed(f.best, 3), 9), "(", f.best_date[6:end], ") -> ",
            rightfield(fixed(f.current, 3), 9), "  n=", rightfield(string(f.n), 2), "  ", persistent)
  end

  # Which operations are hit across MANY columns? A real code regression usually is.
  operations_in_order = String[]
  columns_by_operation = Dict{String, Set{String}}()
  for f in findings
    haskey(columns_by_operation, f.operation) ||
      (push!(operations_in_order, f.operation); columns_by_operation[f.operation] = Set{String}())
    push!(columns_by_operation[f.operation], f.column)
  end
  println("\n=== operations flagged in 3+ columns (a code regression usually crosses columns):")
  for operation in sort(operations_in_order; by = o -> -length(columns_by_operation[o]))
    count = length(columns_by_operation[operation])
    count >= 3 && println("  ", rightfield(string(count), 2), " columns  ", operation)
  end
end

main(ARGS)
