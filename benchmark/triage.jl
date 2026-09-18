# The BORN-SLOW triage: the referee the benchmark instruments lacked.
#
# Every existing check compares a row against itself — the canary against its own frozen baseline,
# a re-sweep against the previous archive, decision 72's speedup against a sibling variant sharing
# the same code path. A defect present from BIRTH is invisible to all of them: `weighted_inner` ran
# Base's serial fold on CPU from the day it shipped, sat in RESULTS.md flat across four thread
# columns at 5x the same-size `inner`, and was found by a CONSUMER computing achieved bandwidth
# against the hardware ceiling (PERFORMANCE.md finding (ac)). This scan asks the two questions no
# instrument asked, over archives that already exist — no new measurement:
#
#   A. THREAD FLATNESS, ON EVERY HOST — an operation whose t1 and tN times coincide on ALL hosts
#      that swept both thread counts. Both halves of the phrasing were forced by measurement. The
#      threshold is 1.1x because a streaming operation saturated at the memory roof legitimately
#      reads 1.1–1.3x at 512^3, and a first run at 1.3x flagged 211 rows, nearly all exactly that.
#      The every-host quantifier is the discriminator the 9800X3D forced: one Zen 5 core pulls
#      close to the full DRAM bandwidth, so on that host `add!` at 512^3 is honestly flat (1.09x,
#      44 GB/s — the roof) while the same row scales 1.5x on the 12700K. Flat on ONE host is that
#      host's physics; flat on EVERY host is a property of the CODE — `weighted_inner` and
#      `reality_residual` read 1.0x on both. Rows below 1 ms at the low thread count are skipped
#      (thread-spawn overhead dominates, PERFORMANCE.md §4(u)).
#
#   B. DECLARED PEERS — pairs of operations whose DOCSTRINGS claim comparable cost, asserted here
#      for the first time. `weighted_inner`'s docstring said "the same traffic as one spectral
#      `inner`" while the operation ran 5–9x slower, and nothing checked cost claims. A class-median
#      comparison was tried first and dropped as noise: a benchmark class mixes algorithms whose
#      work per element legitimately differs by 10–64x (`NUFFT` against a spline gather,
#      `Lalescu(3,3)`'s 512-node stencil against trilinear's 8), so "far from the class median"
#      mostly measured the algorithm, not a defect. A declared pair states WHY the two should be
#      close, so a flag is a broken documented claim rather than a curiosity.
#
# This is a TRIAGE, not a gate (docs/TESTING.md §1): it prints counts and rows and never fails a
# build, because "slower than its class median" has honest false positives and a red gate nobody
# believes is worse than a list somebody reads. A flagged row is closed by fixing it, or by adding
# it to KNOWN below with a pointer to the recorded reason — the same two outcomes a review finding
# has, so the list trends to zero unexplained rows rather than to a tolerated background.

using BenchmarkTools
using Printf

# Rows whose flagging is EXPECTED, each with the recorded reason a reader can chase. A bare prefix
# match keeps one entry per operation family. These stay IN the output, labelled — a known row that
# silently vanished from the list would be a suppressed failure.
const TRIAGE_KNOWN = (
  ("reality_residual", "recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry"),
  ("materialize_kernel", "deliberate materializer + process-history-sensitive — PERFORMANCE.md §4(y)"),
  ("lpnorm", "deliberate materializer — invariant 13's documented exception list"),
  ("radial_correlation", "materializes its power field + inverse transform by design — decision 22"),
  ("cross-correlation", "the radial_correlation co-spectrum form — same materialization"),
  ("weighted_inner", "the finding-(ac) pathology, FIXED 2026-08-30; BOTH hosts are now re-swept (2026-08-31) and the pathology is gone — the only surviving flags are the 64^3 rows, which carry ~1.1 ms of work against a 1 ms floor and are overhead-bound, not the pathology"),
)

_known_note(key) = begin
  i = findfirst(((prefix, _),) -> startswith(key, prefix), TRIAGE_KNOWN)
  i === nothing ? "" : TRIAGE_KNOWN[i][2]
end

# "CPU 12700K t4" -> ("12700K", 4); "CPU t4" -> ("", 4); a GPU label -> nothing.
function _cpu_lane(label)
  m = match(r"^CPU (?:(.+) )?t(\d+)$", label)
  m === nothing && return nothing
  return (something(m.captures[1], ""), parse(Int, m.captures[2]))
end

_row_time(group, class, key) = (haskey(group, class) && haskey(group[class], key)) ?
  time(minimum(group[class][key])) : nothing

"""
    triage_section(groups; flat_ratio = 1.1, floor_ns = 1.0e6, outlier_ratio = 8.0) -> String

The born-slow scan over assembled benchmark lanes, as a Markdown section. The arguments are:

- `groups`: the `(label, BenchmarkGroup)` pairs `report.jl` already loads.
- `flat_ratio`: a CPU row scales if its lowest-thread time exceeds `flat_ratio` times its
  highest-thread time; below that it is flagged flat.
- `floor_ns`: rows faster than this at the low thread count are skipped as overhead-bound.
- `outlier_ratio`: retained for call compatibility; the declared-peer table carries its own caps.
"""
function triage_section(groups; flat_ratio = 1.1, floor_ns = 1.0e6, outlier_ratio = 8.0)
  classes = ("fft", "algebra", "operators", "convolution", "transfer", "reductions", "storage", "resolution")
  io = IOBuffer()
  println(io, "## Triage — the born-slow scan\n")
  println(io, "Two questions no per-row history can answer (finding (ag)): does a threaded operation ",
          "actually scale, and is a row wildly slower than its class peers at the same workload. ",
          "Flags are QUESTIONS, not verdicts — a `known` row carries its recorded reason, and an ",
          "unexplained one is closed by a fix or by a recorded reason, never by deleting the row. ",
          "Thresholds: flat means under ", flat_ratio, "x speedup lowest-to-highest thread lane with ",
          "at least ", BenchmarkTools.prettytime(floor_ns), " of work; an outlier is over ",
          outlier_ratio, "x its class median.\n")

  # ---- A. thread flatness, on every host ----
  hosts = Dict{String, Vector{Tuple{Int, Int}}}()          # host -> [(threads, group index)]
  for (i, (label, _)) in enumerate(groups)
    lane = _cpu_lane(label)
    lane === nothing && continue
    push!(get!(hosts, lane[1], Tuple{Int, Int}[]), (lane[2], i))
  end
  # Per (class, row): the speedup on each host that covers both ends of its thread sweep.
  speedups = Dict{Tuple{String, String}, Vector{Tuple{String, Float64, Float64}}}()
  for (host, lanes) in sort(collect(hosts); by = first)
    length(lanes) < 2 && continue
    sort!(lanes; by = first)
    (n_low, i_low), (n_high, i_high) = lanes[1], lanes[end]
    n_low == n_high && continue
    g_low, g_high = groups[i_low][2], groups[i_high][2]
    for class in classes, key in sort(collect(keys(haskey(g_low, class) ? g_low[class] : Dict{String, Any}())))
      t_low = _row_time(g_low, class, key)
      t_high = _row_time(g_high, class, key)
      (t_low === nothing || t_high === nothing) && continue
      t_low < floor_ns && continue
      push!(get!(speedups, (class, key), Tuple{String, Float64, Float64}[]),
            (host, t_low, t_low / t_high))
    end
  end
  flat_rows = Vector{Tuple{String, String, Vector{Tuple{String, Float64, Float64}}}}()
  for ((class, key), per_host) in sort(collect(speedups); by = first)
    # Every covering host flat: one saturated host is that host's memory physics, not the code's.
    length(per_host) ≥ 1 && all(h -> h[3] < flat_ratio, per_host) &&
      push!(flat_rows, (class, key, per_host))
  end
  known_flat = count(r -> !isempty(_known_note(split(r[2], " | ")[1])), flat_rows)
  println(io, "### A. Thread-flat on every host — ", length(flat_rows), " flagged (", known_flat, " known)\n")
  if !isempty(flat_rows)
    println(io, "| class | row | per-host (t_low, speedup) | note |")
    println(io, "|:--|:--|:--|:--|")
    for (class, key, per_host) in flat_rows
      note = _known_note(split(key, " | ")[1])
      detail = join(("$(h): $(BenchmarkTools.prettytime(t)) ×$(round(sp; digits = 2))"
                     for (h, t, sp) in per_host), "; ")
      println(io, "| ", class, " | ", key, " | ", detail, " | ",
              isempty(note) ? "**UNEXPLAINED**" : "known: " * note, " |")
    end
    println(io)
  end

  # ---- B. declared peers, per lane ----
  # Each entry: (operation-row prefix, peer prefix, cap, the documented claim being asserted).
  # The pair matches rows by identical workload suffix. Grow this table whenever a docstring makes
  # a cost claim — that is what turns prose into an assertion.
  peers = (
    ("weighted_inner vec", "inner spectral", 4.0,
     "the weighted_inner docstring: \"the same traffic as one spectral `inner`\""),
    ("exponential_convolve! vector", "convolve! vector", 5.0,
     "the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back"),
    # The SCALAR pair is deliberately NOT declared. Its ratio measures the documented lazy-vs-stored
    # tradeoff — one exp per mode against a pure stream, which the exponential_convolve! docstring
    # prices explicitly ("choose between this and a stored kernel by reuse") — and with one component
    # there is no fiber to amortize over, so the ratio is large by DESIGN and shrinks only with
    # thread count. The first version declared it, and the freshly re-swept 9800X3D lanes flagged it
    # at ~20x at t2 — a correctly-working operation reported as a violation, which is the
    # class-median mistake in a smaller box. IT item 2's take-or-leave tail (a vectorized exp) is
    # the recorded lever on this cost.
  )
  peer_rows = Vector{NTuple{7, Any}}()
  for (label, group) in groups, class in classes
    haskey(group, class) || continue
    ks = collect(keys(group[class]))
    for (op_prefix, peer_prefix, cap, claim) in peers
      for key in ks
        startswith(key, op_prefix * " |") || continue
        workload = split(key, " | ")[2]
        peer_key_i = findfirst(k -> startswith(k, peer_prefix * " |") && endswith(k, " | " * workload), ks)
        peer_key_i === nothing && continue
        t_op = _row_time(group, class, key)
        t_peer = _row_time(group, class, ks[peer_key_i])
        (t_op === nothing || t_peer === nothing) && continue
        # The same floor as the flatness scan: a microsecond-scale device row is launch-bound, and a
        # ratio of two launch overheads says nothing about either operation.
        t_op < floor_ns && continue
        t_op > cap * t_peer &&
          push!(peer_rows, (label, key, peer_prefix, t_op, t_peer, t_op / t_peer, claim))
      end
    end
  end
  known_peer = count(r -> !isempty(_known_note(r[2])), peer_rows)
  println(io, "### B. Declared-peer violations — ", length(peer_rows), " flagged (", known_peer, " known)\n")
  if !isempty(peer_rows)
    println(io, "| lane | row | peer | time | peer time | ratio | documented claim |")
    println(io, "|:--|:--|:--|:--|:--|:--|:--|")
    for (label, key, peer, t_op, t_peer, ratio, claim) in sort(peer_rows; by = r -> -r[6])
      note = _known_note(split(key, " | ")[1])
      @printf(io, "| %s | %s | %s | %s | %s | %.1fx | %s%s |\n", label, key, peer,
              BenchmarkTools.prettytime(t_op), BenchmarkTools.prettytime(t_peer), ratio, claim,
              isempty(note) ? "" : " — known: " * note)
    end
    println(io)
  end
  return String(take!(io))
end

# Standalone: julia --project=benchmark benchmark/triage.jl results/<lane>.json ...
# The regular route is through report.jl, which includes this file and appends the section to
# RESULTS.md on every regeneration; standalone exists so the scan can be run over any archive set
# without rewriting the report. The label parser is report.jl's, duplicated here in miniature so
# standalone use needs no include that would run the whole report — keep the two in step.
if abspath(PROGRAM_FILE) == @__FILE__
  function _standalone_label(path)
    b = splitext(basename(path))[1]
    startswith(b, "cpu-t") && return replace(b, "cpu-t" => "CPU t")
    (m = match(r"^cpu-(.+)-t(\d+)$", b)) !== nothing &&
      return "CPU " * uppercase(m.captures[1]) * " t" * m.captures[2]
    b in ("gpu", "cuda") && return "GPU"
    startswith(b, "gpu-") &&
      return "GPU " * uppercase(replace(b, "gpu-" => "", "rtx" => "", "rx" => "", "gtx" => ""))
    return b
  end
  standalone_groups = [(_standalone_label(p), BenchmarkTools.load(p)[1]) for p in ARGS]
  print(triage_section(standalone_groups))
end


"""
    triage_selftest(archive_low, archive_high)

Falsify the scan before trusting it (the check-the-check discipline): loading one host's low- and
high-thread archives, it (1) perturbs a copy so a scaling operation reads flat and asserts the scan
flags it as UNEXPLAINED, (2) asserts a scaling operation is NOT flagged unperturbed, and (3) asserts
the known retro-cases (`weighted_inner`, `reality_residual`) flag as known. Run it by hand after
editing the scan; it is not part of any gate, benchmark code having none.
"""
function triage_selftest(archive_low, archive_high)
  g_low = BenchmarkTools.load(archive_low)[1]
  g_high = BenchmarkTools.load(archive_high)[1]
  groups = [("CPU SELFTEST t1", g_low), ("CPU SELFTEST t8", g_high)]

  target = "add! scalar | Float64 512^3"
  haskey(g_low["algebra"], target) || error("selftest fixture missing: $(target)")
  clean = triage_section(groups)
  # Unperturbed: the scaling row must NOT appear flat (it scales 1.5x on the 12700K archives).
  occursin(r"add! scalar \| Float64 512\^3.*UNEXPLAINED", clean) &&
    error("selftest: the scan flags a scaling operation — threshold broken")
  # The retro-cases must appear, as known.
  occursin("weighted_inner", clean) || error("selftest: weighted_inner does not flag — the scan would have missed finding (ac)")
  occursin("reality_residual", clean) || error("selftest: reality_residual does not flag")

  # Perturb: the high-thread lane reports the LOW-thread trial, i.e. threading did nothing.
  g_flat = BenchmarkTools.load(archive_high)[1]
  g_flat["algebra"][target] = g_low["algebra"][target]
  perturbed = triage_section([("CPU SELFTEST t1", g_low), ("CPU SELFTEST t8", g_flat)])
  occursin(r"add! scalar \| Float64 512\^3", perturbed) ||
    error("selftest: a flattened scaler is NOT flagged — the scan is blind to the class it exists for")
  return "triage selftest OK: flags the flattened scaler, spares the true scaler, retro-flags weighted_inner and reality_residual"
end
