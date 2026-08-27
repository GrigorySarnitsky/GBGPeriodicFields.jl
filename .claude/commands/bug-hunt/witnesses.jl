# The witness runner — the mechanical half of /bug-hunt, and the reason the instrument can verify a
# claim rather than believe one. Ported from GBGIsotropicTurbulence 2026-08-27 (mechanism only).
#
# WHY IT EXISTS, and it is the third instance of one class. `hunt.js` asks each lane to run its own
# witness and report `observed: FAILS`. That is the lane reporting on its own evidence — the same
# shape as a verifier lane self-reporting its findings count, and as a grader deciding whether its own
# HONORED claim was earned. Both of those were closed by moving the measurement outside the party
# being measured. This closes the third: a witness is a PROGRAM, so the honest check is to run it.
#
# The instrument's founding rule is that the only admissible evidence is a program that fails. An
# agent's ACCOUNT of a program that fails is not that program.
#
#   julia --startup-file=no .claude/commands/bug-hunt/witnesses.jl <pile-dir> [repo-root]
#
# Exit 0 when every witness behaves as a witness must — FAILING on the current tree. Exit 1 when any
# passes, because a passing witness is not a bug and must not reach a fix pass.
pile = length(ARGS) >= 1 ? ARGS[1] : error("usage: witnesses.jl <pile-dir> [repo-root]")
repo = length(ARGS) >= 2 ? ARGS[2] : pwd()

files = sort(filter(f -> startswith(basename(f), "witness-") && endswith(f, ".jl"),
                    readdir(pile; join = true)))
isempty(files) && (println("NO WITNESSES in $pile — an empty hunt is not a clean tree."); exit(1))

failing, passing, erroring = String[], String[], String[]
for f in files
  name = basename(f)
  # A witness runs under the package's own project, exactly as its lane ran it, so a difference here
  # would be a difference in the harness rather than in the code.
  out = IOBuffer()
  ok = try
    run(pipeline(Cmd(`julia --startup-file=no --project=$repo $f`; dir = repo);
                 stdout = out, stderr = out))
    true
  catch
    false
  end
  text = String(take!(out))
  # Julia's `Test` exits non-zero on a failed @testset, so a non-zero exit is the witness doing its
  # job. An ERROR that is not a test failure is a broken witness — evidence about the witness, not
  # about the package — and is reported apart from both.
  # Distinguishing the two non-passing outcomes needs care, and the obvious test is wrong: a FAILING
  # testset also prints `LoadError`, because a script whose tests fail exits through one. What
  # separates them is WHY the testset did not pass — an assertion that came out false ("Test Failed")
  # is the witness working, while an exception thrown inside it ("Test threw exception", "Error During
  # Test") is the witness broken. Checking for LoadError classified a perfectly good failing witness as
  # broken on the first run of this file.
  threw = occursin("Test threw exception", text) || occursin("Error During Test", text)
  asserted = occursin("Test Failed", text)
  broken = threw && !asserted
  if ok
    push!(passing, name)
    println("PASSES   $name  — NOT A BUG. Discard the candidate however good its argument was.")
  elseif broken
    push!(erroring, name)
    println("ERRORS   $name  — the witness is broken, not the package. Fix it and re-run.")
    for line in Iterators.take(split(strip(text), '\n'), 4)
      println("           ", line)
    end
  else
    push!(failing, name)
    println("FAILS    $name  — a real candidate. This file IS the finding.")
  end
end

println()
println("$(length(failing)) failing, $(length(passing)) passing, $(length(erroring)) erroring, "
        * "$(length(files)) total.")
if !isempty(passing)
  println("A PASSING WITNESS IS NOT A BUG. If a lane reported one of these as FAILS, its account "
          * "disagrees with the program — believe the program.")
end
exit(isempty(passing) ? 0 : 1)
