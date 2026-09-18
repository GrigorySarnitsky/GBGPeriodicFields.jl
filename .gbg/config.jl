# .gbg/config.jl — this package's settings, as data.
#
# Read by `ConfigIO`, which parses this file and evaluates nothing: only literals and the constructors
# of `Model` are accepted. Every field not written here takes its default; write a line only where the
# default is wrong for this package.
Config(
    package = "GBGPeriodicFields",
    tool = v"2.0.0-rc.4",
    docs_build = ["julia", "--project=docs", "docs/make.jl"],
    test = ["julia", "--project", "-e", "using Pkg; Pkg.test()"],
    # The rules page is written by `Render.pages` during the docs build. No rule reads a generated
    # page, which matters here more than usual: a page that states the rules quotes every banned
    # spelling in order to ban it.
    generated = ["docs/src/gbg-rules.md"],
    # The four rationale documents are where this package's mathematics lives, so they are in scope
    # deliberately rather than by the default, which reads none of them.
    filesets = Dict(
        FileSet.RATIONALE => ["docs/ARCHITECTURE.md", "docs/FORMALIZATION.md",
                              "docs/TESTING.md", "docs/PERFORMANCE.md"],
    ),
    switches = [
        Switch(target = Symbol("RULE.TEX.MATHBF"),
               reason = "Deferred, not declined. The one bold string here is the wavenumber vector \
                         in the worked turbulence example, where italic k is the turbulent kinetic \
                         energy and the two would otherwise collide; the notation page states that \
                         and scopes it to the example. Declaring it is one line, and the owner is \
                         holding that line until the bold set can be settled together with \
                         GBGIsotropicTurbulence, whose notation this example follows. Declaring a \
                         set here first would make the fleet agree by coincidence rather than by \
                         decision."),
    ],
)
