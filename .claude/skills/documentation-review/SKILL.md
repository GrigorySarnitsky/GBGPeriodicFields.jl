<!-- gbg:managed begin v2.0.0-rc.7 — rewritten by `gbg sync`; do not edit -->
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
2. Launch the agents: run the ONE driver, `drivers/run.js` of the pinned GBGCodingTools, through the
   `Workflow` tool, with the arguments file the verb just named. Julia cannot launch an agent and
   only this session can, which is why the verb stopped here.
3. `gbg run collect` — reads what the agents wrote. Exit 2 means a role wrote nothing, or the tree
   moved under them; the first is relaunched once, the second is the owner's to answer.
4. `gbg run next` — moves to the next stage and says what it wants. Repeat 2 to 4 until it says the
   run is ready to close.
5. At a FIX stage it writes the open findings instead of launching agents. Fix each in the
   documentation and commit it with `gbg docfix commit --message "…" --finding <id>`, which asks the
   change guard first. `gbg docfix check` says what the change broke. Never edit code here, and never
   change what is inside a math span: a finding that needs either becomes a question for the owner,
   put with `gbg ask "<decision>" --options "<one> | <another>"`.
6. `gbg run close` — writes the record and the report, and puts what is still open on the owner's
   work queue.
## What it may not do

- It never starts another run, never raises the budget, and never edits the instrument.
- It never fixes what it was not asked to fix: this instrument's findings are documentation's, and a code defect becomes a question.
- `gbg run abandon` ends a run the owner does not want continued. Its findings are dropped.

<!-- gbg:managed end -->
