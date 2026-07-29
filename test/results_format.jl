# The committed benchmark report must parse as GFM (external audit BENCH-04).
#
# A benchmark key is "<operation> | <workload>", so every data row carries two label cells before the
# timings. The header declared only `operation`, leaving each table with one more data column than it
# announced — and a Markdown renderer resolves that by DROPPING the overflow, so the last backend
# column disappeared from the rendered page while the committed text still held it. Nothing caught it:
# the file is generated, never parsed, and reading it by field position (as a human or an awk script
# does) gives the right answer, which is exactly why the defect survived being looked at.
#
# This is a text-only check on a committed artifact, so it needs neither the benchmark environment nor
# a device — it belongs in the default suite rather than the opt-in benchmark lane.

using Test

const REPORT_PATH = joinpath(@__DIR__, "..", "benchmark", "RESULTS.md")

@testset "benchmark/RESULTS.md parses as GFM (audit BENCH-04)" begin
  @test isfile(REPORT_PATH)
  lines = readlines(REPORT_PATH)

  cells(line) = length(split(line, '|'))
  header_indices = findall(l -> startswith(l, "| operation "), lines)
  @test !isempty(header_indices)                     # a report with no table is a broken report

  for h in header_indices
    width = cells(lines[h])
    @test startswith(lines[h + 1], "|:--")           # the alignment row
    @test cells(lines[h + 1]) == width
    # Every data row of this table, up to the next blank line or heading.
    row = h + 2
    rows_checked = 0
    while row <= length(lines) && startswith(lines[row], "| ")
      @test cells(lines[row]) == width
      rows_checked += 1
      row += 1
    end
    @test rows_checked > 0                           # a table with a header and no rows is broken
  end

  # Every table must declare the same set of columns, or one column silently means two things.
  widths = unique(cells(lines[h]) for h in header_indices)
  @test length(widths) == 1
end
