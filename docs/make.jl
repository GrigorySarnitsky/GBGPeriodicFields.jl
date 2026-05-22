using Pkg
Pkg.activate(@__DIR__)

function remove_jupyter_files()
  dirs = [joinpath(r, d) for (r, ds, _) in walkdir(@__DIR__) for d in ds if d == ".ipynb_checkpoints"]
  foreach(p -> rm(p; recursive = true), dirs)
end

remove_jupyter_files()

using Documenter
using GBGPeriodicFields


makedocs(
  sitename = "GBGPeriodicFields.jl",
  modules  = [GBGPeriodicFields, GBGPeriodicFields.Fields],
  format   = Documenter.HTML(),
  pages    = [
    "Home" => "index.md",
    "API"  => Any[
      "Overview"          => "api.md",
      "GBGPeriodicFields" => "api/GBGPeriodicFields.md",
      "Fields"            => "api/Fields.md",
    ],
  ]
)

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGPeriodicFields.jl",
  devbranch = "master",
)