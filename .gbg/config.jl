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
        FileSet.RATIONALE => ["docs/ARCHITECTURE.md", "docs/DECISIONS.md",
                              "docs/FORMALIZATION.md", "docs/TESTING.md",
                              "docs/PERFORMANCE.md"],
    ),
    # The one bold string this package writes. It is the wavenumber vector in the worked turbulence
    # example, where italic k is the turbulent kinetic energy and the two would otherwise collide; the
    # notation page states that and scopes it to the example. Declared rather than switched off, so
    # the rule keeps running: a second bold string cannot arrive unnoticed. `\mathbf{1}` needs no
    # entry — every package is granted the identity.
    switches = [
        Switch(target = Symbol("RULE.DOC.RETIRED_CLAIMS"),
               files = ["docs/DECISIONS.md"],
               reason = "A decision log QUOTES a retired claim in order to record that it was \
                         retired: decision 20's entry says a kernel is itself a scalar field and \
                         is immediately followed by decision 60 superseding it. The ban and the \
                         log want opposite things from the same sentence, and the log is right. \
                         This is why the log is its own document: the rule can be narrowed to a \
                         FILE but not to a section, so splitting it turned an unfixable problem \
                         into a one-line switch. Every other rule still reads this file."),
    ],
    settings = [
        Setting(rule = Symbol("RULE.TEX.MATHBF"), name = :mathbf_allowed, value = ["\\mathbf{k}"]),
        # The seven pages a human did not write, which is the set the in-tree lint carried: the four
        # rationale documents, the two hand-written guides, and the Literate example (whose banner is
        # the same text with each line prefixed `# `, since that is what renders as prose).
        # The phrases this package has retired. The old in-tree lint's alternation became two
        # entries, and its `\s+` came out: the check flattens whitespace itself, which is what
        # lets it see a phrase broken across a line wrap.
        Setting(rule = Symbol("RULE.DOC.RETIRED_CLAIMS"), name = :retired_claims, value = [
            RetiredClaim(phrase = "kernel is itself a scalar field",
                         reason = "a field in spectral representation is not a kernel",
                         decision = "decision 60"),
            RetiredClaim(phrase = "kernel is held either as a scalar field",
                         reason = "a kernel is a `SpectralKernel`, not one of two storage roles of a field",
                         decision = "decision 60"),
            RetiredClaim(phrase = "field passed as a kernel",
                         reason = "a bare field does not dispatch as a kernel; it is wrapped in `StoredKernel`",
                         decision = "decision 60"),
            RetiredClaim(phrase = "kernel as a scalar field in spectral representation",
                         reason = "name the kernel class returned (`StoredKernel`, `SeparableKernel`, `RadialKernel`)",
                         decision = "decision 60"),
            RetiredClaim(phrase = "window as a scalar field in spectral representation",
                         reason = "name the kernel class returned (`StoredKernel`, `SeparableKernel`, `RadialKernel`)",
                         decision = "decision 60"),
            RetiredClaim(phrase = "expand it into a scalar field in spectral representation",
                         reason = "`materialize_kernel` returns a `StoredKernel`",
                         decision = "decision 60"),
            RetiredClaim(phrase = "accepted directly wherever a kernel is taken",
                         reason = "a bare `ScalarFieldSpectral` does not dispatch as a kernel",
                         decision = "decision 60"),
            RetiredClaim(phrase = "type cannot tell those apart",
                         reason = "the type is exactly what distinguishes the kernel role from the field role",
                         decision = "decision 60"),
            RetiredClaim(phrase = "squared_wavenumber_field",
                         reason = "use `radial_kernel(identity, multipliers)`",
                         decision = "decision 60"),
            RetiredClaim(phrase = "[CUDA] default_memory",
                         reason = "CUDA.jl 6 reads `default_memory` under [CUDACore], not [CUDA]; see docs/src/gpu.md",
                         decision = "decision 84"),
        ]),
        Setting(rule = Symbol("RULE.DOC.AI_BANNER"), name = :banner_pages, value = [
            "docs/ARCHITECTURE.md", "docs/FORMALIZATION.md", "docs/TESTING.md", "docs/PERFORMANCE.md",
            "docs/src/tutorial.md", "docs/src/gpu.md", "examples/HIST_CPU.jl",
        ]),
    ],
)
