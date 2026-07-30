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

remove_jupyter_files()
copy_rationale_pages()
build_examples()
lint_inline_math()
lint_notation_variants()
lint_api_page_structure()

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
