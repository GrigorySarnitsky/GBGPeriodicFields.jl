using Pkg
Pkg.activate(@__DIR__)
using Literate

function remove_jupyter_files()
  dirs = [joinpath(r, d) for (r, ds, _) in walkdir(@__DIR__) for d in ds if d == ".ipynb_checkpoints"]
  foreach(p -> rm(p; recursive = true), dirs)
end

# Render the design-rationale docs into the site without moving them: ARCHITECTURE.md,
# TESTING.md, and PERFORMANCE.md stay the single sources (referenced by CLAUDE.md), copied
# into src/ at build time. The copies (src/architecture.md, …) are gitignored.
function copy_rationale_pages()
  for name in ("ARCHITECTURE.md", "FORMALIZATION.md", "TESTING.md", "PERFORMANCE.md")
    cp(joinpath(@__DIR__, name), joinpath(@__DIR__, "src", lowercase(name)); force = true)
  end
end

# Build the browsable example page from the runnable script with Literate.jl: the same
# `examples/HIST_CPU.jl` a user downloads becomes the tutorial. Rendered with plain (non-executed)
# code fences, the pre-generated GPU-produced figures (committed under examples/figures/) embedded — so
# the page never runs the DNS in CI — and the script copied beside it for download. Output gitignored.
function build_examples()
  output = joinpath(@__DIR__, "src", "examples")
  figures = joinpath(@__DIR__, "..", "examples", "figures")
  mkpath(output)
  for png in filter(name -> endswith(name, ".png"), readdir(figures))
    cp(joinpath(figures, png), joinpath(output, png); force = true)
  end
  cp(joinpath(@__DIR__, "..", "examples", "HIST_CPU.jl"), joinpath(output, "HIST_CPU.jl"); force = true)
  Literate.markdown(joinpath(@__DIR__, "..", "examples", "HIST_CPU.jl"), output;
                    name = "hist_cpu", documenter = false, execute = false,
                    codefence = "```julia" => "```")
end

# The rendered-doc source set both lints scan: every `src/*.jl` docstring, the four rationale docs, and
# every `docs/src` page except the gitignored rationale COPIES (which are linted from their sources).
function _doc_lint_sources()
  sources = String[]
  for f in readdir(joinpath(@__DIR__, "..", "src"); join = true)
    endswith(f, ".jl") && push!(sources, f)
  end
  for name in ("ARCHITECTURE.md", "FORMALIZATION.md", "TESTING.md", "PERFORMANCE.md")
    push!(sources, joinpath(@__DIR__, name))
  end
  generated = Set(["architecture.md", "formalization.md", "testing.md", "performance.md"])
  for (root, _, files) in walkdir(joinpath(@__DIR__, "src")), f in files
    endswith(f, ".md") && !(f in generated) && push!(sources, joinpath(root, f))
  end
  return sources
end

# Doc lint: an inline ``…`` math span must not be split across a source line by a CommonMark
# list/blockquote leader. A wrapped continuation beginning with "- "/"* "/"+ "/"> "/"1." (≤ 3 leading
# spaces) is parsed as a *new list item*, which silently drops the span out of math mode — and Documenter
# does NOT flag it (the page builds, then renders the LaTeX as literal text). This guard fails the build
# instead; keep each inline span on one source line (break the prose around it, not the span). The α/β
# convolution formula `dst .= α ĝ·f̂ + β dst` wrapping onto a "+ …" line was exactly this bug. Must run
# after `build_examples()` so the generated `examples/hist_cpu.md` (the Literate example's rendered prose)
# exists to be linted.
function lint_inline_math()
  leader = r"^\s{0,3}([-*+>]|\d+[.)])\s"
  twobacktick = r"(?<!`)``(?!`)"
  sources = _doc_lint_sources()
  problems = String[]
  for file in sources
    isjl = endswith(file, ".jl")
    indoc = !isjl                 # .md renders entirely; .jl renders only inside """ … """ docstrings
    infence = false
    inspan = false                # inside an unclosed inline ``…`` span
    for (n, line) in enumerate(eachline(file))
      # This package writes every docstring delimiter as a lone `"""` on its own line, so toggle on that —
      # robust against a triple-quoted string *literal* in code (whose opening `x = """` is never lone).
      if isjl && strip(line) == "\"\"\""
        indoc = !indoc; inspan = false; continue
      end
      indoc || continue
      if startswith(strip(line), "```")
        infence = !infence; inspan = false; continue
      end
      infence && continue
      if inspan && occursin(leader, line)
        push!(problems, string(relpath(file, joinpath(@__DIR__, "..")), ":", n,
                               "  inline ``math`` broken across a line by a list/blockquote leader"))
      end
      isodd(count(twobacktick, line)) && (inspan = !inspan)
    end
  end
  isempty(problems) || error("doc lint failed — keep inline math on one line:\n  " * join(problems, "\n  "))
  @info "doc lint: inline math OK across $(length(sources)) source files"
end

# Doc lint: canonical notation. A rendered-math token with a single house spelling must never appear in a
# banned variant — a silent drift (the source parses, the page renders, yet the notation disagrees with its
# sibling docstring). The allocating `divergence` once wrote its partial as `\partial_i` where `divergence!`
# wrote `\partial_{x_i}`: one operation, one home, one notation (CLAUDE.md §Style, "the review unit is the
# operation family and the cold read"). Extend `banned` as new canonical spellings are fixed.
function lint_notation_variants()
  banned = [
    (r"\\partial_[ijk]",
     "bare-index partial — write \\partial_{x_i} (subscript the coordinate, not the fiber index)"),
    # An unbraced fraction numerator (\frac1{N}, \tfrac12) renders correctly but leaves an argument
    # boundary implicit; the house rule braces every macro argument (notation.md). A braced numerator
    # (\frac{1}{N}) puts a "{" — not a digit — right after frac, so it never trips this. Works on both
    # .md (\frac) and .jl (\\frac) since the match is "…frac<digit>" regardless of the leading escape.
    (r"\\[dt]?frac[0-9]",
     "unbraced fraction argument — brace it: \\tfrac{1}{2}, \\frac{1}{N} (not \\tfrac12 / \\frac1{N})"),
  ]
  srcs = _doc_lint_sources()
  problems = String[]
  for file in srcs, (n, line) in enumerate(eachline(file)), (re, msg) in banned
    occursin(re, line) &&
      push!(problems, string(relpath(file, joinpath(@__DIR__, "..")), ":", n, "  ", msg))
  end
  isempty(problems) || error("doc lint failed — non-canonical notation:\n  " * join(problems, "\n  "))
  @info "doc lint: notation OK across $(length(srcs)) source files"
end

"""
    lint_retired_claims()

Fail the build on a claim the package has retired, matched **across line breaks**.

This exists because [`lint_notation_variants`](@ref) and every hand-run `grep` are line-oriented,
while these docstrings are hard-wrapped — so a banned phrase straddling a wrap point is invisible to
both. Decision 60 stopped a field in spectral representation from being a kernel, and the sweep for
that claim missed `convolve`'s own docstring for exactly this reason: line 949 ended with "a scalar"
and line 950 began with "field in spectral representation". This lint normalizes whitespace over the
whole file first, so a wrap cannot hide a phrase.

`ARCHITECTURE.md`'s §13 decision log is exempt below its heading: it is append-only history by policy,
and its record of what was once true must survive the thing ceasing to be true.
"""
function lint_retired_claims()
  banned = [
    (r"kernel\s+is\s+itself\s+a\s+scalar\s+field",
     "decision 60 — a field in spectral representation is not a kernel"),
    (r"kernel\s+is\s+held\s+either\s+as\s+a\s+scalar\s+field",
     "decision 60 — a kernel is a `SpectralKernel`, not one of two storage roles of a field"),
    (r"field\s+passed\s+as\s+a\s+kernel",
     "decision 60 — a bare field does not dispatch as a kernel; it is wrapped in `StoredKernel`"),
    (r"(?:kernel|window)\s+as\s+a\s+scalar\s+field\s+in\s+spectral\s+representation",
     "decision 60 — name the kernel class returned (`StoredKernel`, `SeparableKernel`, `RadialKernel`)"),
    (r"expand\s+it\s+into\s+a\s+scalar\s+field\s+in\s+spectral\s+representation",
     "decision 60 — `materialize_kernel` returns a `StoredKernel`"),
    (r"accepted\s+directly\s+wherever\s+a\s+kernel\s+is\s+taken",
     "decision 60 — a bare `ScalarFieldSpectral` does not dispatch as a kernel"),
    (r"type\s+cannot\s+tell\s+those\s+apart",
     "decision 60 — the type is exactly what distinguishes the kernel role from the field role"),
    (r"squared_wavenumber_field",
     "removed by decision 60 — use `radial_kernel(identity, multipliers)`"),
  ]
  problems = String[]
  for file in _doc_lint_sources()
    text = read(file, String)
    # §13 is append-only history: lint only what precedes it.
    if endswith(file, "ARCHITECTURE.md")
      cut = findfirst("## 13. Decision log", text)
      cut === nothing || (text = text[1:first(cut)-1])
    end
    flat = replace(text, r"\s+" => " ")
    for (re, msg) in banned
      occursin(re, flat) &&
        push!(problems, string(relpath(file, joinpath(@__DIR__, "..")), "  ", msg))
    end
  end
  isempty(problems) ||
    error("doc lint failed — retired claims still asserted:\n  " * join(problems, "\n  "))
  @info "doc lint: no retired claims"
end

"""
    lint_api_page_structure()

Check the structural rules the API pages follow, which Documenter itself cannot enforce because a
malformed page still BUILDS: an `## Internal API` section must come last, and no `@docs` block may be
empty.

Both failed silently and were only visible in the rendered sidebar. Moving the fiber types to
`FiberSections` appended a "The fiber" section AFTER `Internal API` — which also stranded that
section's `@autodocs` block under the wrong heading, so the rendered Internal API listed the fiber —
and left behind an empty `@docs` block in `Fields.md`, rendering as a heading with nothing under it.
"""
function lint_api_page_structure()
  problems = String[]
  for file in sort(readdir(joinpath(@__DIR__, "src", "api"); join = true))
    endswith(file, ".md") || continue
    text = read(file, String)
    name = relpath(file, joinpath(@__DIR__, ".."))
    sections = [m.captures[1] for m in eachmatch(r"^## (.+)$"m, text)]
    internal = findfirst(==("Internal API"), sections)
    internal === nothing || internal == length(sections) ||
      push!(problems, "$name  `## Internal API` is section $internal of $(length(sections)) — it must come last")
    for m in eachmatch(r"```@docs\n(.*?)```"s, text)
      isempty(strip(m.captures[1])) &&
        push!(problems, "$name  an empty `@docs` block renders as a heading with no content")
    end
  end
  isempty(problems) || error("doc lint failed — API page structure:\n  " * join(problems, "\n  "))
  @info "doc lint: API page structure OK"
end

# ---------------------------------------------------------------------------------------------
# PROSE SHAPE — a RATCHET against accretion. Ported from GBGIsotropicTurbulence 2026-08-27, and
# EXTENDED from its docstrings-only scope to the pages and rationale docs, which is where PF measured
# its own accretion (+34 lines of clause-appending in one fix pass, against -5 in the one file that
# was rewritten rather than appended to).
#
# THE DEFECT IT CATCHES is invisible to every per-finding check, because each edit is locally correct:
# across successive fix passes a docstring or section GROWS, each fix appending a clause to an existing
# sentence instead of rewriting the passage. The docs get longer and worse while no individual change
# is wrong.
#
# WHY A RATCHET AND NOT A THRESHOLD. A hard cap either fires on everything that predates the rule or is
# set so high it never fires — and a check that cries wolf is one the operator learns to wave through,
# which is worse than no check. A ratchet has NOTHING TO TUNE: a unit may not grow past what it already
# is, whatever that is. Its false-positive rate on prose that did not grow is structurally zero, and a
# rewrite BANKS the improvement, because shrinking rewrites the baseline down.
#
# THREE NUMBERS, not one. Total words alone misses a unit that stays the same length while one
# paragraph swells and something else is cut. `longest_paragraph` is the number the append-a-clause
# defect actually moves. `admonitions` catches the other accretion shape — a caveat added per finding
# until the docstring is a list of warnings.
#
# THE UNIT MATTERS FOR PAGES, and this is the extension. `ARCHITECTURE.md`'s decision log is
# append-only BY DESIGN, so ratcheting a whole file would fire on every new decision. The unit is
# therefore a SECTION (a heading) for markdown and a DOCSTRING for source: a new section is allowed
# and gets the newcomer caps, while growth of an EXISTING section is exactly what is caught.
const PROSE_BASELINE = joinpath(@__DIR__, "prose_shape.csv")
const NEW_UNIT_PARAGRAPH_CAP = 120
const NEW_UNIT_ADMONITION_CAP = 3

function _prose_metrics(text)
    paragraphs = split(text, r"\n\s*\n")
    longest = isempty(paragraphs) ? 0 : maximum(length(split(p)) for p in paragraphs)
    (words = length(split(text)), longest = longest, admonitions = count(!isnothing, eachmatch(r"!!! ", text)))
end

function _prose_units()
    units = Dict{String, NamedTuple}()
    for file in filter(f -> endswith(f, ".jl"), readdir(joinpath(@__DIR__, "..", "src"); join = true))
        source = read(file, String)
        for m in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, source)
            body = m.captures[1]
            signature = strip(first(split(body, "\n")))
            isempty(signature) && continue
            units["$(basename(file)) :: $(first(signature, 60))"] = _prose_metrics(body)
        end
    end
    pages = String[]
    for d in (joinpath(@__DIR__), joinpath(@__DIR__, "src"), joinpath(@__DIR__, "src", "api"))
        isdir(d) || continue
        append!(pages, filter(f -> endswith(f, ".md"), readdir(d; join = true)))
    end
    for file in pages
        # The generated copies of the rationale docs are regenerated from their sources; ratchet the
        # source, never the copy, or every build would report the copy as new.
        occursin(joinpath("docs", "src"), file) && basename(file) in
            ("architecture.md", "formalization.md", "testing.md", "performance.md") && continue
        section, buffer = "(preamble)", IOBuffer()
        function flush_section!()
            body = String(take!(buffer))
            isempty(strip(body)) && return
            units["$(basename(file)) § $(first(section, 60))"] = _prose_metrics(body)
        end
        for line in eachline(file)
            # A heading opens a new unit — and so does a TOP-LEVEL NUMBERED ITEM, which is what makes
            # this work on an append-only log. `ARCHITECTURE.md` §13 writes each decision as `NN. **…**`
            # rather than as a heading, so ratcheting the section as a whole would fire on every NEW
            # decision, which is the one growth that is correct by design. Splitting per entry makes a
            # new decision a NEW unit (allowed, newcomer-capped) while editing an existing one grows
            # that entry and is caught — which is the actual defect.
            if startswith(line, "#")
                flush_section!()
                section = strip(replace(line, r"^#+" => ""))
            elseif (m = match(r"^(\d+)\. ", line)) !== nothing
                flush_section!()
                section = "item " * m.captures[1]
                println(buffer, line)
            else
                println(buffer, line)
            end
        end
        flush_section!()
    end
    return units
end

function lint_prose_shape()
    units = _prose_units()
    if get(ENV, "PROSE_SHAPE_BASELINE", "0") == "1" || !isfile(PROSE_BASELINE)
        open(PROSE_BASELINE, "w") do io
            println(io, "unit,words,longest_paragraph,admonitions")
            for k in sort(collect(keys(units)))
                u = units[k]
                println(io, "\"", replace(k, "\"" => "'"), "\",", u.words, ",", u.longest, ",", u.admonitions)
            end
        end
        @info "doc lint: prose-shape baseline WRITTEN ($(length(units)) units) — this is deliberate and shows in the diff"
        return
    end
    baseline = Dict{String, NTuple{3, Int}}()
    for (i, line) in enumerate(eachline(PROSE_BASELINE))
        i == 1 && continue
        m = match(r"^\"(.*)\",(\d+),(\d+),(\d+)$", line)
        m === nothing && continue
        baseline[m.captures[1]] = (parse(Int, m.captures[2]), parse(Int, m.captures[3]), parse(Int, m.captures[4]))
    end
    grown, capped, shrunk = String[], String[], 0
    for k in sort(collect(keys(units)))
        u = units[k]
        key = replace(k, "\"" => "'")
        if haskey(baseline, key)
            w, l, a = baseline[key]
            if u.words > w || u.longest > l || u.admonitions > a
                push!(grown, "$key: words $w->$(u.words), longest paragraph $l->$(u.longest), admonitions $a->$(u.admonitions)")
            elseif u.words < w || u.longest < l || u.admonitions < a
                shrunk += 1
            end
        else
            u.longest > NEW_UNIT_PARAGRAPH_CAP && push!(capped, "$key: new unit, longest paragraph $(u.longest) > $NEW_UNIT_PARAGRAPH_CAP words")
            u.admonitions > NEW_UNIT_ADMONITION_CAP && push!(capped, "$key: new unit, $(u.admonitions) admonitions > $NEW_UNIT_ADMONITION_CAP")
        end
    end
    if !isempty(grown) || !isempty(capped)
        for g in grown;  println("  GREW:   ", g); end
        for c in capped; println("  CAPPED: ", c); end
        error("doc lint failed: prose shape. A unit grew past what it already was, or a new one exceeded " *
              "the newcomer caps. Rewrite the passage rather than appending to it — a rewrite that comes " *
              "out shorter banks the improvement automatically. If the growth is genuinely new content, " *
              "re-baseline deliberately with PROSE_SHAPE_BASELINE=1, which shows in the diff.")
    end
    @info "doc lint: prose shape OK ($(length(units)) units, $shrunk improved)"
end


remove_jupyter_files()
copy_rationale_pages()
build_examples()
lint_inline_math()
lint_notation_variants()
lint_retired_claims()
lint_api_page_structure()
lint_prose_shape()

using Documenter
using GBGPeriodicFields

# Make `using GBGPeriodicFields` available to the `jldoctest` examples (the Getting-started
# tutorial; recursive covers the submodules). `doctest = true` runs and verifies them on every
# build, so the examples cannot drift from the code; add more incrementally.
DocMeta.setdocmeta!(GBGPeriodicFields, :DocTestSetup, :(using GBGPeriodicFields); recursive = true)


makedocs(
  sitename  = "GBGPeriodicFields.jl",
  modules   = [GBGPeriodicFields, GBGPeriodicFields.FiberSections, GBGPeriodicFields.Fields, GBGPeriodicFields.FieldAlgebra, GBGPeriodicFields.DifferentialOperators, GBGPeriodicFields.Convolution, GBGPeriodicFields.Points, GBGPeriodicFields.Interpolation, GBGPeriodicFields.Reductions],
  format    = Documenter.HTML(
    # The canonical URL disambiguates the versioned copies Documenter deploys (dev, stable, each
    # tagged version) for anything that indexes them. It points at the deployment ROOT, not at
    # /stable: no version tag has ever been cut, so Documenter has only ever built dev and
    # /stable/ is a 404 — a canonical pointing at a dead URL being strictly worse than none.
    # The root redirects to whatever the default version is, so it stays correct either way.
    canonical     = "https://grigorysarnitsky.github.io/GBGPeriodicFields.jl",
    collapselevel = 1,
    # The architecture document is deliberately one page (the top-level design doc with its
    # append-only decision log), and its rendered size now exceeds Documenter's default hard
    # size_threshold. Exempt that one page; every other page keeps the guard.
    size_threshold_ignore = ["architecture.md"],
  ),
  checkdocs = :exports,
  doctest   = true,
  pages     = [
    "Home" => "index.md",
    "Getting started" => "tutorial.md",
    "Examples" => "examples/hist_cpu.md",
    "Notation" => "notation.md",
    "API"  => Any[
      "Overview"              => "api.md",
      "GBGPeriodicFields"     => "api/GBGPeriodicFields.md",
      "FiberSections"         => "api/FiberSections.md",
      "Fields"                => "api/Fields.md",
      "FieldAlgebra"          => "api/FieldAlgebra.md",
      "DifferentialOperators" => "api/DifferentialOperators.md",
      "Convolution"           => "api/Convolution.md",
      "Points"                => "api/Points.md",
      "Interpolation"         => "api/Interpolation.md",
      "Reductions"            => "api/Reductions.md",
    ],
    "Design & Internals" => Any[
      "Architecture"  => "architecture.md",
      "Formalization" => "formalization.md",
      "Testing"       => "testing.md",
      "Performance"   => "performance.md",
    ],
  ]
)

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGPeriodicFields.jl",
  devbranch = "master",
)
