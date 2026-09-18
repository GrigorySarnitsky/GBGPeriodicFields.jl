# .gbg/config.jl — this package's settings, as data.
#
# Read by `ConfigIO`, which parses this file and evaluates nothing: only literals and the constructors
# of `Model` are accepted. Every field not written here takes its default; write a line only where the
# default is wrong for this package.
Config(
    package = "GBGPeriodicFields",
    tool = v"2.0.0-rc.5",
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
    # The one bold string this package writes. It is the wavenumber vector in the worked turbulence
    # example, where italic k is the turbulent kinetic energy and the two would otherwise collide; the
    # notation page states that and scopes it to the example. Declared rather than switched off, so
    # the rule keeps running: a second bold string cannot arrive unnoticed. `\mathbf{1}` needs no
    # entry — every package is granted the identity.
    settings = [
        Setting(rule = Symbol("RULE.TEX.MATHBF"), name = :mathbf_allowed, value = ["\\mathbf{k}"]),
        # The seven pages a human did not write, which is the set the in-tree lint carried: the four
        # rationale documents, the two hand-written guides, and the Literate example (whose banner is
        # the same text with each line prefixed `# `, since that is what renders as prose).
        Setting(rule = Symbol("RULE.DOC.AI_BANNER"), name = :banner_pages, value = [
            "docs/ARCHITECTURE.md", "docs/FORMALIZATION.md", "docs/TESTING.md", "docs/PERFORMANCE.md",
            "docs/src/tutorial.md", "docs/src/gpu.md", "examples/HIST_CPU.jl",
        ]),
    ],
)
