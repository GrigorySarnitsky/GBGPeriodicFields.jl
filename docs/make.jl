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

# every `docs/src` page except the gitignored rationale COPIES (which are linted from their sources).

# Doc lint: an inline ``…`` math span must not be split across a source line by a CommonMark
# list/blockquote leader. A wrapped continuation beginning with "- "/"* "/"+ "/"> "/"1." (≤ 3 leading
# spaces) is parsed as a *new list item*, which silently drops the span out of math mode — and Documenter
# does NOT flag it (the page builds, then renders the LaTeX as literal text). This guard fails the build
# instead; keep each inline span on one source line (break the prose around it, not the span). The α/β
# convolution formula `dst .= α ĝ·f̂ + β dst` wrapping onto a "+ …" line was exactly this bug. Must run
# after `build_examples()` so the generated `examples/hist_cpu.md` (the Literate example's rendered prose)
# exists to be linted.

# Doc lint: canonical notation. A rendered-math token with a single house spelling must never appear in a
# banned variant — a silent drift (the source parses, the page renders, yet the notation disagrees with its
# sibling docstring). The allocating `divergence` once wrote its partial as `\partial_i` where `divergence!`
# wrote `\partial_{x_i}`: one operation, one home, one notation (CLAUDE.md §Style, "the review unit is the
# operation family and the cold read"). Extend `banned` as new canonical spellings are fixed.

"""
    lint_swallowed_escapes()

Fail the build on a LaTeX command a Julia docstring will silently EAT.

Inside a triple-quoted docstring the Julia parser resolves escapes before Documenter sees the text,
so LaTeX must carry a doubled backslash. Get it wrong and `\t` becomes a TAB, leaving the docstring
holding "20<TAB>imes" — which is what shipped on 2026-09-03 and rendered as `20imes` on the API page.

Nothing else could see it. The build succeeded, every other lint passed, `guards.sh` passed, and the
source line still LOOKS like LaTeX; only the rendered page shows the damage, and only to someone
reading that paragraph. The escapes Julia consumes silently are `a b e f n r t v`, the octal digits,
and `x`/`u`/`U`, which between them swallow the openings of `alpha`, `beta`, `epsilon`, `frac`,
`nabla`, `rangle`, `times` and `varepsilon`. Every OTHER single-backslash command is an invalid
escape sequence that fails to parse, so it cannot ship — this lint covers the whole silent half.

Scoped to `.jl` docstrings: a `.md` page is not Julia source and takes single backslashes correctly,
and a single-backslash escape in Julia CODE (a newline in an error message) is ordinary.
"""

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

# ---------------------------------------------------------------------------------------------
# REVIEW CLOSURE — the verifier is a BUILD REQUIREMENT, not an instruction.
#
# WHY THIS IS A LINT AND NOT A SENTENCE IN A COMMAND FILE. Both /check-docs and /check-consistency
# documented "run verify-fixes.js and loop until every finding is HONORED", and nothing enforced it.
# On 2026-08-27 a full /check-docs pass was reported as "22 findings, all closed" with the verifier
# never run; when it was finally run against the same work it returned 16.1% honored — 5 HONORED, 21
# LINE-ONLY, 5 UNDONE over 31 findings — including two the fixer had listed in his own written plan
# and forgotten. The rule was in the tree, and its presence read as compliance. That is the defect
# this whole instrument set exists to catch, committed by its author, so the rule moves out of prose
# and into the one place that cannot be skipped: the build's exit code.
#
# WHAT IT CHECKS. A banked findings pile (`NN-<lane>.md` under a `.claude/doc-review*` directory) is
# an OPEN ROUND until every finding in it is closed, and a finding is closed only by an independent
# record: a `HONORED` verdict in `<pile>/closure/NN-<lane>.md`, or an entry in
# `.claude/doc-review-adjudicated.md` naming it. A dismissal written only in a commit message closes
# nothing — that was the exact failure the first run measured, and the verifier graded all three of
# that day's dismissals UNDONE for precisely this reason.
#
# NO PILE MEANS NO OPEN ROUND, so a tree that has never run an instrument builds normally. The escape
# is to CLOSE the round, not to argue with it.
# The doc rules live in GBGCodingTools now. What remains here is the review-closure gate and the
# post-build markup check, neither of which has been shown equivalent to a rule yet: the first is
# coupled to the instruments under `.claude/`, which a later phase replaces, and every perturbation
# that would test the second was caught by a source rule before the site was built.

function lint_review_closure()
    claude = joinpath(@__DIR__, "..", ".claude")
    isdir(claude) || return
    adjudicated_path = joinpath(claude, "doc-review-adjudicated.md")
    adjudicated = isfile(adjudicated_path) ? read(adjudicated_path, String) : ""
    open_rounds = String[]
    ranges = Int[]
    for entry in readdir(claude; join = true)
        isdir(entry) || continue
        base = basename(entry)
        (startswith(base, "doc-review") && !endswith(base, "-prev")) || continue
        # `00-SUMMARY.md` is the CONSOLIDATION's reading aid, not a lane: it is written by the main
        # thread after the hats return, holds no findings of its own, and so parsed as a lane that
        # found nothing — reported as a dead lane on every build. Excluding it by its `00-` prefix
        # keeps the dead-lane check pointed at actual lanes, which are numbered from 01.
        lanes = filter(f -> occursin(r"^(?!00-)\d\d-.*\.md$", basename(f)), readdir(entry; join = true))
        isempty(lanes) && continue
        # A round closed by a process that predates the verifier is exempt, but only by an explicit,
        # committed record — the same shape as the prose ratchet's re-baseline. `CLOSED.md` must say
        # how the round was closed and where the account lives; writing one is a deliberate act that
        # shows in the diff, which is the property that keeps it from becoming a silent escape.
        isfile(joinpath(entry, "CLOSED.md")) && continue
        for lane in lanes
            body = read(lane, String)
            # BOTH heading forms the hats actually emit. `panel.js` asks each hat for "one
            # clearly-formatted section per finding" and prescribes NO heading syntax, so the ten
            # economy hats' `## Finding 1 — title` and the two anchor hats' `## 1. title` are equally
            # compliant. This regex matched only the first, so hats 03 and 04 — the two mathematician
            # ANCHORS, the lanes carrying the round's hardest findings — parsed to zero and were
            # reported as dead lanes. It failed safe (red, not green) and was still wrong: three of
            # eleven OPEN lines were this and the summary artifact, and a gate whose output is mostly
            # noise is one nobody reads.
            findings = length(collect(eachmatch(r"^#{2,4} +(?:Finding +\d+|\d+[.)])"m, body)))
            # A lane that parses to zero is a DEAD LANE unless it says otherwise: an unreadable or
            # truncated banked file is indistinguishable from one that found nothing, and reading it
            # as clean is the same inversion `coverage.py` exists to catch. A genuinely clean lane
            # asserts it in words, which is a claim, where an empty parse is an absence.
            if findings == 0
                occursin(r"\bno findings\b"i, body) && continue
                push!(open_rounds, "$(base)/$(basename(lane)): parses to ZERO findings and does not " *
                                   "state that it found none — a dead lane, not a clean one")
                continue
            end
            verdict_file = joinpath(entry, "closure", basename(lane))
            verdicts = isfile(verdict_file) ? read(verdict_file, String) : ""
            # A verdict file persists between rounds, so a lane that did not re-run leaves its previous
            # verdicts behind and they read as current — which is how a round-1 result was almost
            # reported as a round-2 one. Each file stamps the range it graded, and every lane in a
            # round must agree: lanes at different ranges are not one round.
            # Staleness is read from the FILESYSTEM, never from a field the grader writes. The first
            # design asked each verifier lane to stamp `RANGE:` as its first line; the instruction was
            # in the prompt and all eight lanes ignored it, so the check was vacuous while looking
            # present — asking the graded party to certify its own currency, which is the antipattern
            # this whole gate exists to remove. An mtime is recorded by the OS and needs no compliance.
            if mtime(verdict_file) < mtime(lane)
                push!(open_rounds, "$(base)/$(basename(lane)): verdicts predate the findings they " *
                                   "grade — the lane did not re-run")
                continue
            end
            push!(ranges, floor(Int, mtime(verdict_file) / 21600))  # 6-hour buckets: one round, one sitting
            # Count the VERDICT, never the word. A LINE-ONLY demotion note reads "[DEMOTED: HONORED
            # claimed with no enumerated class surface]", so a bare string count inflated 2 honored
            # verdicts to 6 — in the direction that closes a round early, which is the direction that
            # never gets questioned.
            # The verdict in this file is the GRADER'S OWN, before the verifier's mechanical demotion.
            # The demotion runs in the workflow script's post-processing, and a workflow script cannot
            # write files, so it never reaches the markdown: round 4 banked 30 HONORED while the
            # script's authoritative tally was 23. The gate was reading the flattering artifact and
            # went green on a round with eight findings still open. So apply the same predicate here,
            # over the evidence the file does carry. This is deliberately a TWIN of the predicate in
            # `check-consistency/verify-fixes.js` — edit the two together.
            honored = 0
            for chunk in split(verdicts, r"^#{2,4} +Finding "m)[2:end]
                # Both bold/colon spellings a grader emits: `**Verdict:** X` and `**Verdict**: X`.
                # 14 of this round's 66 verdicts — the whole of hat 03 — used the second, so the lane
                # read as 0 HONORED of 14 while every one of its findings was graded. Still anchored
                # to end-of-line so a demotion note ("[DEMOTED: HONORED claimed …]") cannot match.
                occursin(r"^\*\*Verdict:?\*\*:? *HONORED *$"m, chunk) || continue
                cs = (m = match(r"class_surfaces:?\*{0,2}(.*)"s, chunk)) === nothing ? "" : m.captures[1]
                # EMPTINESS, NOT CONTENT (2026-09-01) — synced with the twin in
                # `check-consistency/verify-fixes.js`, which this comment block already required be
                # edited together and which was patched first, leaving this half stale for a day.
                # The old predicate matched a fixed vocabulary (`site|surface|instance` and a short
                # phrase list) and so demoted every sound answer that used a synonym. Measured on the
                # 2026-08-27 round banked under `.claude/doc-review-checkdocs`: 30 HONORED verdicts,
                # of which the old predicate passed 23 — SEVEN spurious, which is why that round read
                # as having eight findings open when only ONE was. A grader who has swept a class to
                # zero has no `file:line` list to give, so a fully-closed finding demoted by
                # construction and the round could never go green.
                # Teeth kept: an ABSENT or boilerplate class answer still fails, which is the case the
                # rule was written for.
                substantive = length(strip(cs)) >= 60 && occursin(r"\s", cs) &&
                              !occursin(r"^(n/?a|none|see above|as noted)\b"i, strip(cs))
                substantive && (honored += 1)
            end
            # A finding whose title the adjudicated list names is closed by that record instead.
            titles = [strip(m.captures[1]) for m in
                      eachmatch(r"^#{2,4} +(?:Finding +\d+ +[—-]|\d+[.)]) +(.*)$"m, body)]
            dismissed = count(t -> !isempty(t) && occursin(first(t, 40), adjudicated), titles)
            if honored + dismissed < findings
                push!(open_rounds, "$(base)/$(basename(lane)): $(findings) finding(s), " *
                                   "$(honored) HONORED, $(dismissed) adjudicated — $(findings - honored - dismissed) OPEN")
            end
        end
    end
    if !isempty(ranges) && (maximum(ranges) - minimum(ranges)) > 1
        error("doc lint failed: the banked round is incoherent — its verdict files were written more " *
              "than six hours apart, so a lane that did not re-run left its previous verdicts in " *
              "place and they read as current. Re-run the verifier over every lane before reading " *
              "the tally.")
    end
    if !isempty(open_rounds)
        for r in open_rounds; println("  OPEN: ", r); end
        error("doc lint failed: an instrument round is banked but not closed. Run " *
              "`.claude/commands/check-consistency/verify-fixes.js` over the pile (passing that " *
              "instrument's lane names), fix whatever comes back LINE-ONLY / UNDONE / NEW-DEFECT, and " *
              "verify again — the loop runs over the SAME findings, never by re-running the lanes. A " *
              "finding you are deliberately not fixing is closed by recording it in " *
              ".claude/doc-review-adjudicated.md, where a verifier can read it; a reason in a commit " *
              "message closes nothing.")
    end
    @info "doc lint: review closure OK (no open rounds)"
end

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
lint_review_closure()

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
