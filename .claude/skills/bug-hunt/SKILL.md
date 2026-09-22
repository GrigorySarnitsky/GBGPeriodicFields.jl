<!-- gbg:managed begin v2.0.0-rc.7 — rewritten by `gbg sync`; do not edit -->
# /bug-hunt

The code does what its documentation says.

Run it when the owner asks for it, and not otherwise: nothing else starts a run. It ends when
every candidate is confirmed or discarded, once.

**Run it to its end in one sitting.** Every step below is one command, and the run is not finished
until `gbg run close` has written its report. A run left open blocks the next one, and a session
that stopped in the middle has spent its agents for nothing.

## The steps

1. `gbg run bug-hunt` — opens the run and writes the first stage's arguments. Add `--readers open` or
   `--readers both` for the open readers, `--model <name>` to name the careful model, `--sequential`
   to launch one agent at a time. It refuses a tree with uncommitted changes to tracked files.
2. Launch the agents: run the ONE driver, `drivers/run.js` of the pinned GBGCodingTools, through the
   `Workflow` tool, with the arguments file the verb just named. Julia cannot launch an agent and
   only this session can, which is why the verb stopped here.
3. `gbg run collect` — reads what the agents wrote. Exit 2 means a role wrote nothing, or the tree
   moved under them; the first is relaunched once, the second is the owner's to answer.
4. `gbg run next` — moves to the next stage and says what it wants. Repeat 2 to 4 until it says the
   run is ready to close.
5. `gbg run close` — writes the record and the report.
## What it may not do

- It never starts another run, never raises the budget, and never edits the instrument.
- It never fixes what it was not asked to fix: this instrument reports and grades; the code is changed only on the owner's answer.
- `gbg run abandon` ends a run the owner does not want continued. Its findings are dropped.

<!-- gbg:managed end -->
