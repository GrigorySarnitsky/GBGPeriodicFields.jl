using Pkg
Pkg.activate(@__DIR__)

function remove_jupyter_files()
  dirs = [joinpath(r, d) for (r, ds, _) in walkdir(@__DIR__) for d in ds if d == ".ipynb_checkpoints"]
  foreach(p -> rm(p; recursive = true), dirs)
end

# Render the design-rationale docs into the site without moving them: ARCHITECTURE.md
# and TESTING.md stay the single sources (referenced by CLAUDE.md), copied into src/ at
# build time. The copies (src/architecture.md, src/testing.md) are gitignored.
function copy_rationale_pages()
  for name in ("ARCHITECTURE.md", "TESTING.md")
    cp(joinpath(@__DIR__, name), joinpath(@__DIR__, "src", lowercase(name)); force = true)
  end
end

remove_jupyter_files()
copy_rationale_pages()

using Documenter
using GBGPeriodicFields

# Make `using GBGPeriodicFields` available to any `jldoctest` examples in docstrings
# (recursive covers the submodules). No doctests exist yet; this is the plumbing so
# examples can be added incrementally and verified on every build.
DocMeta.setdocmeta!(GBGPeriodicFields, :DocTestSetup, :(using GBGPeriodicFields); recursive = true)


makedocs(
  sitename  = "GBGPeriodicFields.jl",
  modules   = [GBGPeriodicFields, GBGPeriodicFields.Fields, GBGPeriodicFields.FieldAlgebra, GBGPeriodicFields.DifferentialOperators, GBGPeriodicFields.Interpolation],
  format    = Documenter.HTML(
    canonical     = "https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/stable",
    collapselevel = 1,
  ),
  checkdocs = :exports,
  doctest   = true,
  pages     = [
    "Home" => "index.md",
    "API"  => Any[
      "Overview"              => "api.md",
      "GBGPeriodicFields"     => "api/GBGPeriodicFields.md",
      "Fields"                => "api/Fields.md",
      "FieldAlgebra"          => "api/FieldAlgebra.md",
      "DifferentialOperators" => "api/DifferentialOperators.md",
      "Interpolation"         => "api/Interpolation.md",
    ],
    "Design & Internals" => Any[
      "Architecture" => "architecture.md",
      "Testing"      => "testing.md",
    ],
  ]
)

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGPeriodicFields.jl",
  devbranch = "master",
)
