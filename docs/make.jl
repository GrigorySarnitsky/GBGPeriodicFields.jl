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
  for name in ("ARCHITECTURE.md", "DECISIONS.md", "FORMALIZATION.md", "TESTING.md", "PERFORMANCE.md")
    cp(joinpath(@__DIR__, name), joinpath(@__DIR__, "src", lowercase(name)); force = true)
  end
end

# Build the browsable example page from the runnable script with Literate.jl: the same
# `examples/HIST_CPU.jl` a user downloads becomes the tutorial. Rendered with plain (non-executed)
# code fences, the pre-generated GPU-produced figures (committed under examples/figures/) embedded — so
# the page never runs the DNS in CI — and the script copied beside it for download. Output gitignored.
#
# `documenter = true` is load-bearing and was `false` until 2026-09-01: with it false, Literate rewrites
# every Documenter admonition into a plain blockquote, so this page alone rendered the AI-provenance
# banner as quoted text while the other five got an info box. The flag costs an `EditURL` block at the
# top of the generated markdown, which is a gain — it links the page back to the runnable script — and
# the `codefence` override below still keeps the fences plain and unexecuted.
function build_examples()
  output = joinpath(@__DIR__, "src", "examples")
  figures = joinpath(@__DIR__, "..", "examples", "figures")
  mkpath(output)
  for png in filter(name -> endswith(name, ".png"), readdir(figures))
    cp(joinpath(figures, png), joinpath(output, png); force = true)
  end
  cp(joinpath(@__DIR__, "..", "examples", "HIST_CPU.jl"), joinpath(output, "HIST_CPU.jl"); force = true)
  Literate.markdown(joinpath(@__DIR__, "..", "examples", "HIST_CPU.jl"), output;
                    name = "hist_cpu", documenter = true, execute = false,
                    codefence = "```julia" => "```")
end

# The doc rules live in GBGCodingTools. What remains here is the post-build markup check below,
# which has not yet been shown equivalent to a rule. `lint_review_closure`, which held the old
# in-tree review instruments' banked rounds to closure, went with those instruments on 2026-10-06.

# `lint_prose_shape` lived here and is RETIRED (2026-09-18): `RULE.DOC.SHAPE` in GBGCodingTools does
# the same job over a superset of the files — it also reads `ext/`, which this lint never did — and
# `gbg check --rebaseline` replaces `PROSE_SHAPE_BASELINE=1`. `docs/prose_shape.csv` stays: the rule
# reads and writes that same file. Keeping both was impossible rather than merely redundant, since
# whichever re-baselined last left the other reading its numbers wrongly.

# The AI-provenance banner is `RULE.DOC.AI_BANNER`'s now, and the pages it covers are declared as
# `banner_pages` in `.gbg/config.jl`. The rule compares the text VERBATIM and strips the `# `
# prefix a Literate file carries, which is what the constant that stood here existed to express.


remove_jupyter_files()
copy_rationale_pages()
build_examples()

using Documenter
using GBGCodingTools
using GBGPeriodicFields

const ROOT = normpath(joinpath(@__DIR__, ".."))

# The one tooling page — what the documentation is held to, a link to the rulebook on GBGCodingTools'
# site, and this package's switches with their reasons. It is written AFTER the lints above: those
# eight walk `docs/src` from disk and know nothing of `generated`, so a page written earlier would
# become their input.
GBGCodingTools.Render.pages(GBGCodingTools.ConfigIO.read_config(ROOT), ROOT)

# Make `using GBGPeriodicFields` available to the `jldoctest` examples (the Getting-started
# tutorial; recursive covers the submodules). `doctest = true` runs and verifies them on every
# build, so the examples cannot drift from the code; add more incrementally.
DocMeta.setdocmeta!(GBGPeriodicFields, :DocTestSetup, :(using GBGPeriodicFields); recursive = true)


GBGCodingTools.makedocs(ROOT;
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
    # Two documents are deliberately one page each, and both carry an APPEND-ONLY log that grows
    # with the project: the architecture doc's decision log, and the performance doc's numbered
    # findings. Their rendered size exceeds Documenter's default hard size_threshold for that
    # reason rather than through padding, and splitting either would break the numbering that the
    # rest of the corpus cites by (decision 78, finding (ae)). Exempt those two; every other page
    # keeps the guard, which is what catches a page that grew by accident.
    size_threshold_ignore = ["decisions.md", "performance.md"],
  ),
  checkdocs = :exports,
  doctest   = true,
  pages     = [
    "Home" => "index.md",
    "Getting started" => "tutorial.md",
    "Running on a GPU" => "gpu.md",
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
      "Decision log"  => "decisions.md",
      "Formalization" => "formalization.md",
      "Testing"       => "testing.md",
      "Performance"   => "performance.md",
      "Documentation tooling" => "gbg.md",
    ],
  ]
)

# A markdown emphasis marker survives into the RENDERED text only when the parser gave up on it,
# so finding one in prose IS the defect — no judgement required. `docs/src/index.md` carried
# `*pairs a section against a **measure***`, an emphasis nesting CommonMark cannot resolve, and it
# rendered as literal asterisks in the Home page's opening paragraph.
#
# It shipped past everything. The deterministic battery HAS a built-HTML surface, but all four of
# its questions are about `@docs`/`@autodocs` placement — nothing ever read the rendered PROSE and
# asked whether any markup had failed to render. The panel's `style-editor` hat reads the raw built
# HTML for exactly this class and did not report it; the `cold-reader` hat reads the Home page and
# did not either. The seeded calibration has no broken-markup class, so the recall of every
# instrument against it was not merely zero but never asked. A reader found it.
#
# This runs AFTER `makedocs` because it reads the built page. Code, `pre` and math are stripped
# first, since a literal `*` or `_` is legitimate inside them; Documenter emits client-side KaTeX as
# raw `$…$` and `\[…\]` in the text, which is why those are stripped as text rather than as tags.
function lint_rendered_markup(build_dir)
  isdir(build_dir) || return
  offenders = String[]
  for (root, _, files) in walkdir(build_dir), file in files
    file == "index.html" || continue
    path = joinpath(root, file)
    html = read(path, String)
    html = replace(html, r"<(code|pre|script|style)\b.*?</\1>"is => " ")
    m = match(r"<article\b.*?</article>"is, html)
    m === nothing || (html = m.match)
    text = replace(html, r"<[^>]+>" => " ")
    text = replace(text, r"\\\[.*?\\\]"s => " ")
    text = replace(text, r"\$[^\$\n]*\$" => " ")
    for line in split(text, '\n')
      chars = collect(line)
      for mm in eachmatch(r"\*\*?[^\s*]|(?<![\w\\])__[^\s_]", line)
        at = length(collect(SubString(line, 1, prevind(line, mm.offset)))) + 1
        lo = max(1, at - 70); hi = min(length(chars), at + 80)
        push!(offenders, "$(relpath(path, build_dir)): …$(join(split(String(chars[lo:hi]))," "))…")
      end
    end
  end
  if !isempty(offenders)
    for o in unique(offenders); println("  RENDERED-MARKUP: ", o); end
    error("doc lint failed: markdown emphasis rendered literally on a built page. The source " *
          "nests emphasis in a way CommonMark cannot resolve (`*a **b***` is the usual shape) — " *
          "rewrite so the spans do not overlap, e.g. `*a* **b**.")
  end
  @info "doc lint: rendered markup OK (no emphasis marker survived into prose)"
end

lint_rendered_markup(joinpath(@__DIR__, "build"))

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGPeriodicFields.jl",
  devbranch = "master",
)
