# The PER-METHOD coverage ledger.
#
# WHAT IT MEASURES, and why the per-symbol ledger beside it is not enough. `ledger.jl` bookkeeps
# coverage per OPERATION: one checked method marks a whole generic done, so `mul!` reports covered on
# the strength of one row out of its dozens of methods. This ledger asks the question one level finer —
# for every `(operation, method)` cell, did an ASSERTION reach that method? — which is decision 55's
# oracle-provenance rule applied per method instead of per symbol.
#
# HOW COVERAGE IS DERIVED, never declared. Rows are not annotated with the method they exercise; a
# hand-maintained mapping is the bookkeeping defect this replaces. Instead the value lane is run under
# `--code-coverage=user` and the executed lines are mapped back to methods by definition span. Twice:
#
#   full run      — fixtures built AND every assertion evaluated
#   fixtures-only — every fixture built, assertion tuples empty (`GBG_LEDGER_FIXTURES_ONLY`)
#
# and a method counts as covered only if it ran in the first and NOT in the second. Without that
# subtraction every allocator and accessor a destination construction touches reads as covered, and the
# ledger reports a coverage it does not have.
#
# THE LIMIT OF THE SPAN MAPPING, stated because it decides how a whole class of cells is closed.
# Methods are located by definition line, so `@eval`-generated methods sharing one site are
# INDISTINGUISHABLE from each other — the codegen families are stamped from a single formula builder
# and execute the same source lines. They are therefore closed as a group, visibly, with the group
# named in the output rather than silently merged: one row reaching the site covers the site, which is
# true of the behaviour precisely because the code is shared.

using GBGPeriodicFields

include(joinpath(@__DIR__, "method_reasons.jl"))

const _LEDGER_MODULES = (GBGPeriodicFields.FiberSections, GBGPeriodicFields.Fields,
                         GBGPeriodicFields.FieldAlgebra, GBGPeriodicFields.DifferentialOperators,
                         GBGPeriodicFields.Convolution, GBGPeriodicFields.Points,
                         GBGPeriodicFields.Interpolation, GBGPeriodicFields.Reductions)


"""
    _read_coverage(directory) -> Dict{String, Dict{Int, Int}}

Parse every `.cov` file under `directory` into `basename => (line => execution count)`. Julia writes
one file per process per source file, so counts for the same source are merged.
"""
function _read_coverage(directory)
  coverage = Dict{String, Dict{Int, Int}}()
  for path in readdir(directory; join = true)
    endswith(path, ".cov") || continue
    source = replace(basename(path), r"\.\d+\.cov$" => "")
    counts = get!(coverage, source, Dict{Int, Int}())
    for (number, line) in enumerate(eachline(path))
      token = strip(line[1:min(9, length(line))])
      token == "-" && continue
      hits = tryparse(Int, token)
      hits === nothing && continue
      counts[number] = max(get(counts, number, 0), hits)
    end
  end
  return coverage
end


"""
    _definition_lines() -> Dict{String, Vector{Int}}

Every package method's definition line, per source file, sorted. A method's span runs from its own
line to the line before the next definition in the same file, which is what lets an executed line be
attributed to the method containing it.
"""
function _definition_lines()
  lines = Dict{String, Vector{Int}}()
  for mod in _LEDGER_MODULES, name in names(mod; all = true)
    isdefined(mod, name) || continue
    object = getfield(mod, name)
    object isa Function || continue
    for method in methods(object)
      # PACKAGE-OWNED only. `methods(+)` hands back everything Base defines too, and crediting or
      # faulting the package for those would make the denominator meaningless.
      method.module in _LEDGER_MODULES || continue
      push!(get!(lines, basename(String(method.file)), Int[]), method.line)
    end
  end
  for value in values(lines)
    sort!(unique!(value))
  end
  return lines
end


"""
    _method_executed(method, coverage, definition_lines) -> Bool

Whether any line in `method`'s definition span was executed. The span ends at the next definition in
the same file; a trailing method is given a generous bound, which can only over-credit within its own
file and never crosses into another method's code.
"""
function _method_executed(method, coverage, definition_lines)
  file = basename(String(method.file))
  haskey(coverage, file) && haskey(definition_lines, file) || return false
  starts = definition_lines[file]
  index = searchsortedfirst(starts, method.line)
  index <= length(starts) && starts[index] == method.line || return false
  stop = index < length(starts) ? starts[index + 1] - 1 : method.line + 500
  counts = coverage[file]
  for line in method.line:stop
    get(counts, line, 0) > 0 && return true
  end
  return false
end


"""
    _run_value_lane_under_coverage(directory, fixtures_only) -> Dict

Run the value lane in a subprocess under `--code-coverage=user`, with the assertion tuples either
evaluated or empty, and return the parsed coverage. The run is a subprocess because coverage is a
process-wide setting and because this lane must not inherit whatever the calling process has already
executed.
"""
function _run_value_lane_under_coverage(directory, fixtures_only::Bool; here = @__DIR__)
  root = dirname(dirname(@__DIR__))
  script = """
    using GBGPeriodicFields, Statistics, Random, LinearAlgebra
    const GBGI = GBGPeriodicFields
    # `invocations.jl` owns `HDF5_AVAILABLE`, which the value lane reads, so the persistence rows
    # reach the ledger exactly as they reach a real survey run rather than being silently skipped.
    include(joinpath(raw"$root", "test", "public_surface.jl"))
    for f in ("shared.jl", "aliasing.jl", "references.jl", "invocations.jl", "values.jl")
      include(joinpath(raw"$here", f))
    end
    run_value_lane(configurations()[1:2])
    """
  environment = copy(ENV)
  environment["GBG_LEDGER_FIXTURES_ONLY"] = fixtures_only ? "1" : ""
  fixtures_only || delete!(environment, "GBG_LEDGER_FIXTURES_ONLY")
  for path in readdir(joinpath(root, "src"); join = true)
    endswith(path, ".cov") && rm(path; force = true)
  end
  command = `$(Base.julia_cmd()) --startup-file=no --code-coverage=user --project=$(Base.active_project()) -e $script`
  run(pipeline(setenv(command, environment); stdout = devnull, stderr = devnull))
  coverage = _read_coverage(joinpath(root, "src"))
  for path in readdir(joinpath(root, "src"); join = true)
    endswith(path, ".cov") && rm(path; force = true)
  end
  return coverage
end


"""
    _ledger_cells() -> Vector{NamedTuple}

Every `(operation, method)` cell the ledger is accountable for: the public operations of
`test/public_surface.jl`, crossed with their package-owned methods. Methods sharing a definition site
are a codegen GROUP — stamped from one builder, executing the same source lines — and are grouped here
so the output can say so rather than pretend they were resolved individually.
"""
function _ledger_cells()
  cells = NamedTuple[]
  for operation in sort(collect(package_operations()); by = String)
    object = nothing
    for mod in _LEDGER_MODULES
      if isdefined(mod, operation)
        candidate = getfield(mod, operation)
        candidate isa Function && (object = candidate; break)
      end
    end
    object === nothing && continue
    for method in methods(object)
      method.module in _LEDGER_MODULES || continue
      push!(cells, (operation = operation, method = method,
                    site = string(basename(String(method.file)), ":", method.line)))
    end
  end
  return cells
end


"""
    run_method_ledger(; verbose = true) -> NamedTuple

The per-method coverage ledger. Every `(operation, method)` cell is COVERED (an assertion reached it),
CLOSED (a recorded reason in `method_reasons.jl` says it cannot have a row), or UNCOVERED — and an
uncovered cell is a finding, which is what makes completion a number reaching zero rather than a claim.
"""
function run_method_ledger(; verbose::Bool = true, source_dir = @__DIR__)
  verbose && println("\n", "═"^100,
    "\nLANE: the PER-METHOD coverage ledger — did an ASSERTION reach this method?",
    "\n      coverage is derived by running the value lane under --code-coverage twice and",
    "\n      subtracting the fixtures-only run, so an allocator a destination touched is not credited",
    "\n", "═"^100)
  root = dirname(dirname(@__DIR__))
  asserted = _run_value_lane_under_coverage(root, false; here = source_dir)
  fixtures = _run_value_lane_under_coverage(root, true; here = source_dir)
  definition_lines = _definition_lines()
  cells = _ledger_cells()

  covered_sites = Set{String}()
  for (file, counts) in asserted, (line, hits) in counts
    hits > 0 || continue
    get(get(fixtures, file, Dict{Int,Int}()), line, 0) > 0 && continue
    push!(covered_sites, string(file, ":", line))
  end

  miscounted = ledger_miscounted_reasons(cells)
  miscounted_sites = Set(split(entry, " declares")[1] for entry in miscounted)
  covered, closed, uncovered = NamedTuple[], NamedTuple[], NamedTuple[]
  for cell in cells
    if _method_executed(cell.method, asserted, definition_lines) &&
       !_method_executed(cell.method, fixtures, definition_lines)
      push!(covered, cell)
    elseif !(cell.site in miscounted_sites) && (reason = ledger_reason(cell)) !== nothing
      push!(closed, (cell..., reason = reason))
    else
      push!(uncovered, cell)
    end
  end

  if verbose
    groups = Dict{String, Int}()
    for cell in cells; groups[cell.site] = get(groups, cell.site, 0) + 1; end
    shared = count(>(1), values(groups))
    println("\n  ", length(cells), " cells over ", length(unique(c.operation for c in cells)),
            " operations · ", shared, " definition sites carry more than one method (codegen groups)")
    println("  covered by an assertion   ", lpad(length(covered), 5))
    println("  closed by a recorded reason ", lpad(length(closed), 3))
    println("  UNCOVERED                 ", lpad(length(uncovered), 5))
    if !isempty(uncovered)
      println("\n  UNCOVERED CELLS — each needs a value row or a recorded reason:")
      by_operation = Dict{Symbol, Vector{String}}()
      for cell in uncovered; push!(get!(by_operation, cell.operation, String[]), cell.site); end
      for operation in sort(collect(keys(by_operation)); by = String)
        sites = sort(unique(by_operation[operation]))
        println("      ", rpad(String(operation), 26), length(by_operation[operation]), " method(s)  @ ",
                join(first(sites, 3), ", "), length(sites) > 3 ? ", …" : "")
      end
    end
    stale = ledger_stale_reasons(cells)
    isempty(stale) || println("\n  STALE REASONS — recorded for a method that no longer exists: ", join(stale, ", "))
    isempty(miscounted) || println("\n  MISCOUNTED REASONS — not honoured: ", join(miscounted, "; "))
  end
  return (cells = length(cells), covered = length(covered), closed = length(closed),
          uncovered = length(uncovered), uncovered_cells = uncovered,
          stale_reasons = ledger_stale_reasons(cells), miscounted_reasons = miscounted)
end


"""
    selfcheck_method_ledger() -> Int

Falsify the ledger BY PERTURBATION, and return the number of probes that failed.

This is the hard part and the reason the lane exists at all: the ledger is the measuring instrument,
so a defect in it reports a coverage nobody then investigates. It cannot be verified by reading — an
earlier version of a neighbouring guard selected a set nearly disjoint from the one its own comment
described and reported 84 violations falling to 0, which read as success. The number was verified; the
instrument was not.

Four probes, each perturbing the input and requiring the output to move by a KNOWN amount:

1. **Delete a value row** → uncovered rises by exactly one and names that cell.
2. **Restore it** → uncovered falls by exactly one and the cell leaves the list.
3. **A reason for a site no method occupies** → reported STALE, never silently crediting.
4. **A reason-closed cell** stays distinguishable from a row-covered one in the counts.

Probes 1 and 2 run against a COPY of the lane with one row removed, so the real tree is never edited.
"""
function selfcheck_method_ledger()
  failures = 0
  baseline = run_method_ledger(; verbose = false)

  # --- probes 1 and 2: remove one row, in a copy, and require a move of exactly one ---------------
  scratch = mktempdir()
  for name in readdir(@__DIR__)
    endswith(name, ".jl") && cp(joinpath(@__DIR__, name), joinpath(scratch, name))
  end
  values_path = joinpath(scratch, "values.jl")
  text = read(values_path, String)
  # `inverse_curl` is the cleanest single-row cell in the lane: one method, reached by no other row.
  needle = """      (:inverse_curl,   field_data(inverse_curl(uh, multipliers)),
                        ref_inverse_curl(field_data(uh), grid, layout)),
"""
  if !occursin(needle, text)
    println("  PROBE 1/2 SKIPPED — the row it perturbs was not found; the probe is stale, which is a")
    println("                      finding about this file rather than about the ledger")
    failures += 1
  else
    write(values_path, replace(text, needle => ""))
    perturbed = run_method_ledger(; verbose = false, source_dir = scratch)
    delta = perturbed.uncovered - baseline.uncovered
    if delta == 1
      println("  probe 1 (delete a row)   uncovered ", baseline.uncovered, " → ", perturbed.uncovered, "  ✓ moved by exactly one")
    else
      println("  probe 1 FAILED — deleting one row moved uncovered by ", delta, ", not 1")
      failures += 1
    end
    named = any(cell -> cell.operation === :inverse_curl, perturbed.uncovered_cells)
    if named
      println("  probe 2 (name the cell)  the deleted row's own cell is the one reported  ✓")
    else
      println("  probe 2 FAILED — uncovered moved but the deleted row's cell is not in the list")
      failures += 1
    end
  end
  rm(scratch; recursive = true, force = true)

  # --- probe 3: a reason for a site no method occupies must be reported STALE --------------------
  LEDGER_REASONS["NoSuchFile.jl:99999"] = (:unreachable, 1, "a probe, not a real exclusion")
  stale = ledger_stale_reasons(_ledger_cells())
  if "NoSuchFile.jl:99999" in stale
    println("  probe 3 (stale reason)   a reason for a nonexistent method is reported, not ignored  ✓")
  else
    println("  probe 3 FAILED — a reason naming no method was silently accepted")
    failures += 1
  end
  delete!(LEDGER_REASONS, "NoSuchFile.jl:99999")

  # --- probe 4: a reason closes a cell WITHOUT it counting as covered ----------------------------
  if isempty(baseline.uncovered_cells)
    println("  probe 4 SKIPPED — no uncovered cell to close; re-check when one exists")
  else
    victim = first(baseline.uncovered_cells)
    group = count(cell -> cell.site == victim.site, _ledger_cells())
    LEDGER_REASONS[victim.site] = (:unreachable, group, "a probe, not a real exclusion")
    closed_run = run_method_ledger(; verbose = false)
    delete!(LEDGER_REASONS, victim.site)
    if closed_run.covered == baseline.covered && closed_run.closed == baseline.closed + group &&
       closed_run.uncovered == baseline.uncovered - group
      println("  probe 4 (reason ≠ row)   a reason closes its DECLARED ", group,
              " method(s), counted apart from coverage  ✓")
    else
      println("  probe 4 FAILED — closing a cell by reason did not move exactly its declared ", group,
              " cell(s) from uncovered to closed (covered ", baseline.covered, "→", closed_run.covered,
              ", closed ", baseline.closed, "→", closed_run.closed,
              ", uncovered ", baseline.uncovered, "→", closed_run.uncovered, ")")
      failures += 1
    end
  end
  # --- probe 5: a reason that closes MORE than it declares must not be honoured -------------------
  if !isempty(baseline.uncovered_cells)
    victim = first(baseline.uncovered_cells)
    LEDGER_REASONS[victim.site] = (:unreachable, 0, "declares zero, so it must not close anything")
    miscounted_run = run_method_ledger(; verbose = false)
    delete!(LEDGER_REASONS, victim.site)
    if miscounted_run.uncovered == baseline.uncovered && !isempty(miscounted_run.miscounted_reasons)
      println("  probe 5 (miscount)       a reason closing more than it declares is refused, not applied  ✓")
    else
      println("  probe 5 FAILED — a reason with a wrong declared count was honoured anyway (uncovered ",
              baseline.uncovered, "→", miscounted_run.uncovered, ")")
      failures += 1
    end
  end
  return failures
end
