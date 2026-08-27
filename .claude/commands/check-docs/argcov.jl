# Argument coverage — the second of /check-docs' two non-grep backstops, extracted from check-docs.md
# 2026-08-27 alongside guards.sh and doi_crosscheck.py.
#
# THE RULE. Every argument in a docstring's SIGNATURE — positional and keyword — must be documented in
# its body. The sweep is driven FROM THE SIGNATURE rather than from the prose, because that is the only
# direction that can see an omission: an argument surfacing only inside a formula reads as "bound by
# use" and a self-contained read of the text never notices it is undocumented.
#
# ONE TRAP, PRESERVED FROM THE ORIGINAL AND WORTH KEEPING VISIBLE: use `prevind`, never `c-1`. The
# α/β/σ arguments are multibyte, and a StringIndexError aborts the sweep at the FIRST file — leaving
# the other eight unscanned while the run still looks like it completed. That is the same
# silent-partial-coverage failure the panel's under-grading check exists for, one instrument over.
#
# Triage, not verdicts: a thin wrapper that @ref-links its home may name a math variable in a ``f``
# span rather than `f`; the α/β accumulation is documented under its Greek name; internal `_helpers`
# are looser by rubric.
#
# THE FIXTURE THIS MUST BE FALSIFIED AGAINST, and it must carry a KEYWORD. PF's first falsification
# used `real_op(destination, source, weight)` — no semicolon — so it passed while the parser was
# discarding the last positional of every keyword-carrying signature. A fixture that cannot reach the
# broken branch proves nothing about it.
#
#   f(a, b, c)              one undocumented -> caught
#   f(a, b, c; opt = 1)     the LAST POSITIONAL undocumented -> caught   <- the arm that was missing
#   "Allocating form of ..." -> exempt
#   _helper(a, b, c)        -> exempt
#   f(a, b)                 -> exempt (prose form)
#
# AND WRITE THE FIXTURE CAREFULLY. PF's first keyword fixture said "`gamma` is NOT mentioned in
# backticks anywhere" — in backticks — so the tool correctly found it documented and the arm read as a
# failure of the fix. The fixture was wrong before the tool was. IT hit the identical trap in its own
# copy on the same day.
#
#   Usage: julia --startup-file=no .claude/commands/check-docs/argcov.jl [repo-root]
# Split a signature's argument list into its parameter NAMES.
#
# THE BUG THIS REPLACES, because it was silent and it was load-bearing. The original split the list on
# commas and then took `split(piece, ";")[end]` — so for `f(a, b, c; opt = 1)` the final comma-piece
# "c; opt = 1" collapsed to "opt", and `c` — THE LAST POSITIONAL ARGUMENT — was discarded. Every
# signature carrying a keyword lost one argument, silently, and the sweep could not report it however
# undocumented it was. Found by the IT session in its own copy, which had reported ZERO for as long as
# the script existed and was being read as a clean corpus; PF inherited the same line from PF's own
# check-docs.md. The semicolon is split FIRST, once, and each side is then split on commas.
#
# `prevind`/`nextind`, never index arithmetic: α/β/σ are multibyte and a StringIndexError aborts the
# sweep at the first file while the run still looks complete.
function signature_parameters(inside::AbstractString)
  semi = findfirst(';', inside)
  positional = semi === nothing ? inside : inside[1:prevind(inside, semi)]
  keywords = semi === nothing ? "" : inside[nextind(inside, semi):end]
  names = String[]
  for raw in vcat(split(positional, ","), split(keywords, ","))
    name = strip(split(split(raw, "::")[1], "=")[1])
    occursin(r"^[A-Za-z][A-Za-z0-9_!]*$", name) && push!(names, String(name))
  end
  return names
end

root = length(ARGS) >= 1 ? ARGS[1] : "."
findings = 0
prose_form = 0
internal = 0
wrappers = 0
for file in sort(filter(f -> endswith(f, ".jl"), readdir(joinpath(root, "src"); join = true)))
  s = read(file, String)
  for m in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, s)
    body = m.captures[1]
    sig = strip(first(split(body, "\n")))
    (occursin("(", sig) && occursin(")", sig)) || continue
    o = findfirst("(", sig).start
    c = findlast(")", sig).start
    inside = sig[nextind(sig, o):prevind(sig, c)]
    # THE RUBRIC'S OWN THRESHOLD, applied here so the output is signal rather than noise. A docstring
    # documenting three or more arguments, OR any keyword, uses the bulleted `The arguments are:` form
    # where each argument is backticked; with fewer and no keyword the rubric REQUIRES the arguments to
    # be bound in running prose instead, where a backtick is not expected. Scanning those produced 204
    # candidates, almost all of them correct-by-rubric — and a sweep reporting 204 non-defects is worse
    # than no sweep, because it gets ignored. Prose binding is not machine-checkable; that half stays a
    # human read, and this reports the half that is.
    parameters = signature_parameters(inside)
    has_keyword = occursin(";", inside)
    # The rubric's other explicit exemption: an internal `_`-prefixed helper "documents its arguments
    # in whatever form reads best", because the threshold exists to keep a USER-FACING argument list
    # findable and the codegen builders are read beside their code. Counted, not silently dropped.
    if startswith(strip(sig), "_")
      global internal += 1
      continue
    end
    # The rubric's third exemption: a THIN ALLOCATING WRAPPER "documents no arguments at all, leading
    # with the one-sentence meaning and `@ref`-linking the home", so the threshold never applies to it.
    # PF spells those one way — "Allocating form of [`f!`](@ref)" — which makes the exemption
    # detectable rather than a judgement call.
    if occursin("Allocating form of", body)
      global wrappers += 1
      continue
    end
    if length(parameters) < 3 && !has_keyword
      global prose_form += 1
      continue
    end
    for p in parameters
      if !occursin(Regex("`\\Q" * p * "\\E`"), body)
        println(basename(file), ": ", sig, "  UNDOCUMENTED `", p, "`")
        global findings += 1
      end
    end
  end
end
println("\n", findings, " undocumented-argument candidate(s) in bulleted-form docstrings — triage each.")
println(wrappers, " thin allocating wrapper(s) skipped by the rubric's exemption.")
println(internal, " internal `_`-prefixed helper(s) skipped by the rubric's exemption.")
println(prose_form, " docstring(s) skipped: fewer than three arguments and no keyword, where the rubric\n"
        * "  requires prose binding rather than backticks. That half is a human read, not a grep.")
