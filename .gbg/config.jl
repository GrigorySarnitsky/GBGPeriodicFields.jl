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
        Switch(target = Symbol("RULE.DOC.SHAPE"),
               files = ["docs/ARCHITECTURE.md", "docs/FORMALIZATION.md",
                        "docs/TESTING.md", "docs/PERFORMANCE.md"],
               reason = "These four are under a ratchet of this package's own — `lint_prose_shape` in \
                         docs/make.jl, whose committed baseline lets a unit shrink and never grow, \
                         where this rule caps a newcomer and then stops watching. The two are not \
                         redundant, they are INCOMPATIBLE: they disagree about whether a numbered \
                         item's own line belongs to its unit, so the rule reported 108 units the \
                         ratchet passes, and they share ONE file, docs/prose_shape.csv, so whichever \
                         re-baselines last leaves the other reading its numbers wrongly. This is an \
                         accommodation between two instruments, not a judgement that either is \
                         right: each was found wrong on one axis on 2026-09-18 — the ratchet \
                         dropped a line per numbered entry and both merged entries that restart \
                         numbering — and both were repaired the same day. The ratchet holds these \
                         four files for one reason: this package pins the tool at `:dev`, an \
                         absolute path on one machine, so the rule does not run on the second host \
                         or in CI, where the ratchet does. When the pin becomes a release, retiring \
                         `lint_prose_shape` and dropping this switch is the better end state. \
                         Everywhere else in the package this rule is on.",
        ),
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
