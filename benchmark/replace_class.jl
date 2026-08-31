# Replace one op-class in an existing lane archive with a freshly measured one.
#
# The case this exists for: a HARNESS defect invalidates one class's rows while the package itself is
# unchanged, so re-sweeping the whole lane would re-measure correct rows for nothing and add a fresh
# round of run-to-run noise to every other column of RESULTS.md. Re-measuring the one class and
# splicing it changes exactly the rows that were wrong and leaves the rest BIT-IDENTICAL, which this
# tool verifies rather than asserts. The motivating incident is PERFORMANCE.md finding (ak): the
# transfer class's `ordered` rows had been timing a stale visit order since decision 78 shipped.
#
# A splice is only honest while the PACKAGE is identical across the two measurements — the archive's
# `commit=` tag exists to stop a column silently claiming HEAD's feature state, so check `git diff
# <archive commit> HEAD -- src/` is empty before using this. If `src/` moved, re-sweep the lane
# instead; this tool cannot tell, and will not pretend to.
#
#   julia --project=benchmark benchmark/replace_class.jl <archive.json> <fresh.json> <class>
#
# The original is copied to `<archive>.pre-<class>-repair` first, and an existing backup is NEVER
# overwritten, so the pristine archive survives a second run. Verification failure THROWS, and the
# archive is restored from that backup before the error propagates — a half-written archive is worse
# than an unrepaired one (finding (ai): an improvised merge destroyed four sweeps by cleaning up
# before its error was read).
using BenchmarkTools

length(ARGS) == 3 || error("usage: replace_class.jl <archive.json> <fresh.json> <class>")
archive_path, fresh_path, class = ARGS

archive = BenchmarkTools.load(archive_path)[1]
fresh = BenchmarkTools.load(fresh_path)[1]

haskey(archive, class) || error("class $(repr(class)) is not in the archive $(archive_path)")
haskey(fresh, class) || error("class $(repr(class)) is not in the fresh run $(fresh_path)")

archive_rows = Set(keys(archive[class]))
fresh_rows = Set(keys(fresh[class]))
if archive_rows != fresh_rows
  missing_rows = sort(collect(setdiff(archive_rows, fresh_rows)))
  extra_rows = sort(collect(setdiff(fresh_rows, archive_rows)))
  # A row-set mismatch means the two runs did not sweep the same grids/types, so the splice would
  # silently drop or add rows. Refuse and name them; the caller re-runs with matching CHAR_* flags.
  error("row sets differ in class $(class):\n" *
        "  in archive only ($(length(missing_rows))): $(join(missing_rows, ", "))\n" *
        "  in fresh only ($(length(extra_rows))): $(join(extra_rows, ", "))")
end

backup_path = "$(archive_path).pre-$(class)-repair"
ispath(backup_path) && error("backup $(backup_path) already exists — refusing to overwrite the " *
                             "pristine original; move it aside first")
cp(archive_path, backup_path)

# The untouched classes, captured BEFORE the write, so verification compares against the original
# rather than against whatever was just written.
before = Dict((c, k) => archive[c][k].times for c in keys(archive) if c != class for k in keys(archive[c]))

archive[class] = fresh[class]
BenchmarkTools.save(archive_path, archive)

try
  back = BenchmarkTools.load(archive_path)[1]
  untouched_ok = all(back[c][k].times == times for ((c, k), times) in before)
  spliced_ok = all(back[class][k].times == fresh[class][k].times for k in keys(fresh[class]))
  # Both directions on the row inventory too: nothing gained, nothing lost anywhere in the archive.
  inventory_ok = Set((c, k) for c in keys(back) for k in keys(back[c])) ==
                 Set(vcat(collect(keys(before)), [(class, k) for k in keys(fresh[class])]))
  println("class $(class): $(length(fresh[class])) rows spliced | ",
          "untouched bit-identical: $(untouched_ok) ($(length(before)) rows) | ",
          "spliced matches fresh: $(spliced_ok) | inventory: $(inventory_ok)")
  (untouched_ok && spliced_ok && inventory_ok) ||
    error("SPLICE VERIFICATION FAILED for $(archive_path)")
catch
  cp(backup_path, archive_path; force = true)
  @error "verification failed — archive restored from $(backup_path)"
  rethrow()
end
