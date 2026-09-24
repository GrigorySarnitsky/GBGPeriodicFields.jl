<!-- gbg:managed begin v2.0.0-rc.23 — rewritten by `gbg sync`; do not edit -->
# /documentation-review

Documentation is true to the code, correct, consistent and self-contained; the change guard, the checks and a verifier agent check each fix.

Run it when the owner asks for it, and not otherwise: nothing else starts a run. It ends when
nothing is open after its last pass, or the owner ended it.

**Run it to its end in one sitting.** Every step below is one command, and the run is not finished
until `gbg run close` has written its report. A run left open blocks the next one, and a session
that stopped in the middle has spent its agents for nothing.

## The steps

1. `gbg run documentation-review` — opens the run and writes the first stage's arguments. Add `--readers open` or
   `--readers both` for the open readers, `--model <name>` to name the careful model, `--sequential`
   to launch one agent at a time. It refuses a tree with uncommitted changes to tracked files.
2. Launch the agents with the `Workflow` call the verb just printed: the driver at the path it names,
   copied into the run's own scratch, with the arguments file beside it. Never the pinned package's
   own `drivers/run.js`, which `Workflow` refuses because it lies outside the working directory. Julia
   cannot launch an agent and only this session can, which is why the verb stopped here.
3. `gbg run collect` — reads what the agents wrote. Exit 2 means a role wrote nothing, or the tree
   moved under them; the first is relaunched once, the second is the owner's to answer.
4. `gbg run next` — moves to the next stage and says what it wants. Repeat 2 to 4 until it says the
   run is ready to close.
5. At a FIX stage it writes the open findings instead of launching agents. Fix each in the
   documentation and commit it with `gbg docfix commit --message "…" --finding <id>`, which asks the
   change guard first. `gbg docfix check` says what the change broke. Never edit code or the config
   here, and never change a formula — what the page renders as mathematics; turning a code span into
   a math span with the same text, or back, is the one respelling allowed. A finding whose fix needs
   any of those is PARKED for the owner with `gbg run park <id> --why "<what it would change>"`: a
   question about it stands, and no pass works on it until he answers.
6. `gbg run close` — writes the record and the report, and puts what is still open on the owner's
   work queue. COMMIT `.gbg/runs/<id>/` yourself: `gbg docfix commit` leaves it out on purpose, and
   nothing else commits it. Where a fix ADDED information and so raised a prose-shape number, the
   re-baseline is a SEPARATE commit AFTER the close, with its reason — never inside a fix pass,
   where it would be a code change ending the run and would let a raise pass as a fix. A run ENDED EARLY with `gbg run abandon` keeps its
   record only if an agent RAN, and is committed the same way; one that launched nothing is deleted by the
   verb, id and all, and any findings it was carrying go back to the run that found them.
## What it may not do

- It never starts another run, never raises the budget, and never edits the instrument.
- It never fixes what it was not asked to fix: this instrument's findings are documentation's, and a code defect becomes a question.
- `gbg run abandon` ends a run the owner does not want continued. Its findings are dropped.

<!-- gbg:managed end -->
