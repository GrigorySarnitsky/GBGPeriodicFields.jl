# Merge per-grid part archives into one lane archive — the §4(q) workaround's missing tool.
#
# A single `-t8` characterize.jl process segfaults on `Enteropia` inside FFTW's threaded executor
# (PERFORMANCE.md §4(q)), so that lane is swept one grid per process and merged. The merge was
# improvised each time, and on 2026-08-31 an improvised one destroyed four sweeps: the script threw
# (assigning `tags` on an immutable struct) and an UNCONDITIONAL cleanup deleted the parts before
# anyone read the error. This tool is that lesson: it verifies the merge in BOTH directions — every
# part row present bit-equal, nothing extra — and THROWS rather than half-succeeding, so a caller
# has no reason to clean up on faith. Delete parts only after this exits 0.
#
#   julia --project=benchmark benchmark/merge_parts.jl <parts_dir> <out.json> <N1> <N2> ...
using BenchmarkTools

parts_dir, out = ARGS[1], ARGS[2]
sizes = ARGS[3:end]
parts = [BenchmarkTools.load(joinpath(parts_dir, "t8-part-$N.json"))[1] for N in sizes]
merged = BenchmarkGroup()
append!(merged.tags, parts[1].tags)             # one sweep, one vintage: parts share their commit stamp
total = 0
for part in parts, class in keys(part), key in keys(part[class])
  haskey(merged, class) || (merged[class] = BenchmarkGroup())
  haskey(merged[class], key) && error("row collision across parts: $class / $key")
  merged[class][key] = part[class][key]
  global total += 1
end
BenchmarkTools.save(out, merged)
back = BenchmarkTools.load(out)[1]
forward = all(all(time(minimum(back[c][k])) == time(minimum(p[c][k]))
                  for c in keys(p) for k in keys(p[c])) for p in parts)
count_back = sum(length(keys(back[c])) for c in keys(back); init = 0)
println("rows merged: ", total, " | forward: ", forward, " | reverse: ", count_back == total)
(forward && count_back == total) || error("MERGE VERIFICATION FAILED — do not delete the parts")
