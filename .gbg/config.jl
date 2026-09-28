# .gbg/config.jl — this package's settings, as data.
#
# Read by `ConfigIO`, which parses this file and evaluates nothing: only literals and the constructors
# of `Model` are accepted. Every field not written here takes its default; write a line only where the
# default is wrong for this package.
Config(
    package = "GBGPeriodicFields",
    tool = v"2.0.0-rc.36",
    docs_build = ["julia", "--project=docs", "docs/make.jl"],
    test = ["julia", "--project", "-e", "using Pkg; Pkg.test()"],
    # The one tooling page, written by `Render.pages` during the docs build: what the documentation
    # is held to, a link to the rulebook, and this package's switches. No rule reads a generated page.
    generated = ["docs/src/gbg.md"],
    filesets = Dict(
        # The default set is four files: the two examples and the two scripts the CPU example calls.
        # The scripts are not Literate surfaces and are dropped; BOTH examples stay. This package has
        # treated the ROCm example as a rendered surface since it was written — its full-line comments
        # carry the same mathematics under the same rules, and the site not rendering it does not make
        # it private — so losing it to a narrowing aimed at the scripts would be an accident.
        FileSet.LITERATE => ["examples/HIST_CPU.jl", "examples/gpu/rocm/HIST_ROCm.jl"],
    ),
    # The fields whose experts read this package's documentation. Differential geometry carries
    # `RULE.DOC.COORD_FREE` and is the bundle-and-section framing the architecture rests on; the other
    # two are open readers, reporting what is wrong in their field that no rule names. Turbulence
    # theory is deliberately absent: invariant 12 keeps physics in the consumer, so a turbulence expert
    # would be reading for a science this package does not contain.
    disciplines = [:differential_geometry, :spectral_numerics, :software_architecture],
    # The docs build copies each rationale document into `docs/src/` as a lowercase sibling, and the
    # copy is what the site renders. A fix belongs in the source; the change guard refuses one landing
    # in a copy, which the next build would overwrite.
    copies = [
        "docs/src/architecture.md" => "docs/ARCHITECTURE.md",
        "docs/src/decisions.md" => "docs/DECISIONS.md",
        "docs/src/formalization.md" => "docs/FORMALIZATION.md",
        "docs/src/testing.md" => "docs/TESTING.md",
        "docs/src/performance.md" => "docs/PERFORMANCE.md",
    ],
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
        Switch(target = Symbol("RULE.API.POSITIONAL"),
               files = ["src/Fields.jl"],
               reason = "ONLY `Grid3D`'s two-argument constructor's `origin` keyword. It shifts every \
                         node, so the rule points the other way; the owner weighed that against the \
                         churn on 2026-09-02 and kept the keyword, the four-argument constructor taking \
                         it positionally. Every other argument in this file still follows the rule."),
        Switch(target = Symbol("RULE.API.POSITIONAL"),
               files = ["src/Fields.jl"],
               reason = "ONLY the `array_type` keyword of the constructors that build a field by \
                         sampling a function. It picks the storage family the result lives in, not \
                         any value; making it positional would be an interface change breaking the \
                         consumer's calls for a consistency gain only. Owner-decided 2026-09-25 \
                         (finding 2026-09-24-documentation-review-01-009). Every other argument in \
                         this file still follows the rule."),
        Switch(target = Symbol("RULE.API.POSITIONAL"),
               files = ["src/Interpolation.jl"],
               reason = "ONLY the callable field's `scheme` keyword, `field(x; scheme = …)`. A \
                         one-point convenience whose default is the usual case; owner-settled \
                         2026-08-05, while `interpolate`/`anterpolate` keep `scheme` positional. Every \
                         other argument in this file still follows the rule."),
        Switch(target = Symbol("RULE.API.POSITIONAL"),
               files = ["src/Reductions.jl"],
               reason = "ONLY the `corrected` keyword of `var`, `std` and `cov`. These EXTEND \
                         `Statistics`, whose own methods spell it as a keyword; a positional form would \
                         break the drop-in standard-library use the package promises. Owner-decided \
                         2026-09-25 (finding 2026-09-24-documentation-review-01-009). Every other \
                         argument in this file still follows the rule."),
    ],
    settings = [
        Setting(rule = Symbol("RULE.TEX.MATHBF"), name = :mathbf_allowed, value = ["\\mathbf{k}"]),
        # The one document where matrix and flattening machinery belongs. Unset, the rule reads as
        # "and nowhere", which is the wrong statement for a package that keeps its component
        # expansions in exactly one place.
        Setting(rule = Symbol("RULE.DOC.COORD_FREE"), name = :formalization,
                value = "docs/FORMALIZATION.md"),
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
