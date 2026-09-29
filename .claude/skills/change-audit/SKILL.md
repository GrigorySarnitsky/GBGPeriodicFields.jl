<!-- gbg:managed begin v2.0.0-rc.47 — rewritten by `gbg sync`; do not edit -->
# /change-audit

A code change is no wider than the defect and the owner's direction and still accepts input that worked before; it grades the fix and changes nothing.

Run it when the owner asks for it, and not otherwise: nothing else starts a run. It ends when
one pass over the change.

**Run it to its end in one sitting.** Every step below is one command, and the run is not finished
until `gbg run close` has written its report. A run left open blocks the next one, and a session
that stopped in the middle has spent its agents for nothing.

## The steps

1. `gbg run change-audit` — opens the run and writes the first stage's arguments. Add `--readers open` or
   `--readers both` for the open readers, `--model <name>` to name the careful model, `--sequential`
   to launch one agent at a time. It refuses a tree with uncommitted changes to tracked files.
2. Launch the agents with the `Workflow` call the verb just printed: the driver at the path it names,
   copied into the run's own scratch with the stage's arguments spliced in, so the call passes no
   args. Never the pinned package's own `drivers/run.js`, which `Workflow` refuses because it lies
   outside the working directory. Julia cannot launch an agent and only this session can, which is
   why the verb stopped here.
3. Save what the `Workflow` RETURNED — the whole object — as `returned.json` in the stage's own
   directory, which the verb named: the collect falls back on it for an agent whose result file never
   appeared. Then `gbg run collect`, which reads what the agents wrote. Exit 2 means a role wrote
   nothing, or the tree moved under them; the first is relaunched once, the second is the owner's to
   answer.
4. `gbg run cost <dir>` — records what the stage's agents cost, from the transcripts under the
   directory the `Workflow` result names (the one holding its `journal.jsonl`). The launch's own
   token figure counts a tenth of the real cost; the transcripts are the source. Then
   `gbg run next`, which moves to the next stage and says what it wants. Repeat 2 to 4 until it says
   the run is ready to close.
5. `gbg run close` — writes the record and the report.
## What it may not do

- It never starts another run, never raises the budget, and never edits the instrument.
- It never fixes what it was not asked to fix: this instrument reports and grades; the code is changed only on the owner's answer.
- `gbg run abandon` ends a run the owner does not want continued. Its findings are dropped.

<!-- gbg:managed end -->
