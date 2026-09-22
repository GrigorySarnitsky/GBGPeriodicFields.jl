# The rc.5 → rc.7 upgrade ran the old version twice, and neither failure announced itself

**Status: open.** Both were worked around in PF and PF is clean at rc.7 (92 rules, 18 generated
paths, both gates exit 0, commit `eeea5440`). Nothing here is a request to change PF. Delete this
file when it is concluded.

Found on `Enteropia` following `docs/PF-WIRING.md` at `v2.0.0-rc.7`, on PF at `03534c53`. The
document is otherwise accurate: every claim checked held, including the four file parameters, the
line numbers in `docs/make.jl`, the four-file Literate set and the 2,756-line `CLAUDE.md`.

## 1. `gbg bump` writes the OLD version's files under the NEW version's banner

`bump` runs whatever the manifest holds — which, before the manifests move, is the version being
upgraded FROM. So it wrote rc.5's generated content and stamped rc.7 on it. The result was 17 files
changed with 17 insertions and 17 deletions: one line each, every one a version string.

The tree then misdescribed itself, and a reader has no way to tell:

- `.gitignore` opened `# gbg:managed begin v2.0.0-rc.7` above rc.5's content.
- `.gbg/policy/00-index.md` announced eight files and 98 rules, under the same banner, where rc.7
  is nine files and 92 rules.
- The four files rc.7 adds — `asking.md` and the three `.claude/skills/*/SKILL.md` — were not
  written at all, because rc.5's generators do not know them. `PF-WIRING.md` lists them as
  products of the bump and measured 20 rewritten paths on a fresh clone; this run rewrote 16.

Running `gbg sync` again after the manifests moved fixed it completely (14 paths at rc.7, the four
new files among them). **The document does not say to do this**, and between the bump and that sync
the package sat in a state where every generated file claimed a version whose content it did not
carry. Two candidate fixes: have `bump` refuse to write generated files when the manifest's version
differs from the pin it is setting, or have it re-exec under the new version once the pin is written.

## 2. `Pkg.resolve()` moved the rev label without fetching the tag

`PF-WIRING.md` §Step 1 says `Pkg.instantiate()` does not move a changed rev and only `Pkg.resolve()`
does. On this machine `Pkg.resolve()` did not move it either, in a way that is worse than not moving
it: it rewrote `repo-rev = "v2.0.0-rc.7"` into both manifests **while keeping rc.5's content hash**.

    git-tree-sha1 = 9fe9694cd9bee765b9821ae2a04a3fd7f99c2c15   # this is the tree of v2.0.0-rc.5
    repo-rev      = "v2.0.0-rc.7"

The cause is that Pkg's own clone had never fetched the tag — it held `v2.0.0-rc.1` through `rc.5`
and nothing later. `Pkg.update("GBGCodingTools")` fetched and repaired both environments
(`git-tree-sha1 = eb5cf923…`, which is rc.7's tree).

**This is a recurrence.** The same thing happened here at rc.4 → rc.5 and is recorded in this
session's notes: resolve and instantiate both reported success while leaving the old revision in
place. It is worth stating in the document as the expected step rather than the fallback.

## What caught both

`gbg run next` answering `unknown verb run`, which `PF-WIRING.md` prescribes as the check that the
version took. It is the only thing in the upgrade that would have noticed either failure, and it
caught both. Worth keeping, and worth saying that it is load-bearing rather than a formality.

## One consequence for other packages

Both manifests are gitignored, so the pin travels through git and the resolved content does not.
Every machine and every sibling package repeats this, and the failure is silent on each. Whatever
fix is chosen should assume the manifest is stale rather than that someone read the instruction.

## 3. `RULE.CIT.RESOLVES` reads a `[` inside a math span as a markdown link

Added after the upgrade, running `gbg check --network` as the document directs. It reports one
finding against PF and the finding is wrong; PF has not been changed to satisfy it.

    RULE.CIT.RESOLVES  docs/ARCHITECTURE.md:1035  https://doi.org/10.1016/j.jcp.2009.10.046
    resolves to "Implementation of high order spline interpolations for tracking test particles
    in discretized fields", not to "<eighteen lines of unrelated prose>"

The DOI is correct: it resolves to exactly the work the reference names. The reference itself is at
line **1053**, is well-formed, and its link text is that same title character for character:

    - C. C. Lalescu, B. Teaca, D. Carati, [*Implementation of high order spline interpolations for
      tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046),
      J. Comput. Phys. **229**(17) (2010) 5862–5869.

What the rule anchored on is line 1035, which reads

    ``[o_a, o_a + L_a)`` per axis — origin-aware, …

a half-open interval inside a LaTeX math span. The `[` is unmatched, because a half-open interval
has no closing bracket. The link parser takes it as a link opening, scans forward for the next
`](`, finds the DOI eighteen lines later, and calls everything in between the title.

Two things follow. The parser should not look for links inside a ``…`` math span or a `…` code
span — PF's own style rule requires interval notation to be LaTeX rather than code, so this
spelling is mandatory here and will recur in any package that writes intervals. And a title
captured across a blank line is never a title: a length or newline bound would have turned this
into no finding rather than a confusing one.

Worth saying plainly, since the network rule is new and this was its first real run: its one
finding on this package is a false positive, and the honest reading of `gbg check --network` on PF
today is that all fifteen DOIs resolve to the works their titles name.

## 4. BLOCKER — `drivers/run.js` does not parse at rc.7, so no instrument can launch

The owner asked for the first documentation review. `gbg run documentation-review` opened
`2026-09-22-documentation-review-01` correctly — 23 built pages, 26 roles, arguments written. The
launch then failed, and it fails for every instrument and every stage, because the ONE driver is not
valid JavaScript. Line 72:

    .map((l) => `- ${l.file}${l.node ? ` (${l.node})` : ''}: "${l.text}"${l.found === 'OUTDATED' ? '  [not found again — read the file's changed regions]' : ''}`)

The single-quoted string `'  [not found again — read the file's changed regions]'` contains an
unescaped apostrophe in `file's`. The literal ends at `file'`, and what follows is not an expression.
The harness rejects the script before any agent starts:

    Script parse error: Unexpected token (72:135)

It is the only instance of its class in the file: one grep for a single-quoted string containing an
apostrophe returns this line and nothing else. The fix is one character — escape it, or use a
template or double quotes. **Not applied here**, on the owner's word: PF runs the pinned driver or it
does not run, and a driver patched in one consumer is the drift this package exists to end.

Two things this says about the apparatus rather than about the line.

**The defect is in the branch that reports a stale quote** — `l.found === 'OUTDATED'`, the path taken
when a finding's anchor is no longer where it was. A fixture run whose quotes all resolve never
renders that string, and the file parses only when nothing has moved. That is why it survived to a
tag: the whole file fails to parse regardless of which branch runs, but only a real run with a stale
anchor would have made anyone look.

**Nothing on the Julia side can see it.** `test/driver.jl` is described as reading this file and
requiring it to read every key Julia writes; whatever it does, it does not check that the file is
parseable JavaScript. A syntax check would have caught this in a second, needs no agent and no
network, and is the cheapest possible gate on the one file every instrument depends on.

### One integration defect met on the way, minor beside the above

The `Workflow` tool refuses a `scriptPath` outside the working directory, so
`~/.julia/packages/GBGCodingTools/<slug>/drivers/run.js` cannot be named directly. PF copied it
byte for byte into `.gbg/scratch/`, which is gitignored, and launched from there; the copy was
verified identical by hash. It works, but the instruction "run `drivers/run.js` of the pinned
GBGCodingTools through the `Workflow` tool" cannot be followed literally, and every consumer will
hit it. Worth either saying so in `PF-WIRING.md` or having `gbg run` place the copy itself, where it
can also record which driver a run actually used.

## 5. BLOCKER — the driver cannot write its result files, because workflow scripts have no filesystem

rc.8 fixed the parse error of §4 and the driver now parses. The launch fails at the next step, and
this one is architectural rather than a typo. `writeResult`, the single path by which every agent's
findings reach disk:

    async function writeResult(path, value) {
      const fs = await import('node:fs/promises');
      await fs.mkdir(path.replace(/\/[^/]+$/, ''), { recursive: true });
      await fs.writeFile(path, JSON.stringify(value, null, 2));
    }

The harness refuses it before any agent starts:

    SyntaxError: import() is not available in workflow scripts.

And the restriction is wider than the syntax. The workflow-authoring reference states, of the script
sandbox: **"No filesystem or Node.js API access."** So the call fails twice over — `import()` is
rejected outright, and a static import would find no `fs` to bind. There is no spelling of that
function that works. It is the only filesystem use in the file, and it is the load-bearing one.

The comment directly above it records the reasoning, which is sound and is exactly what cannot be had
here:

    // The result files are what `gbg run collect` reads. Written here rather than returned, because
    // the return value of a workflow is read by a session and the collector is a separate program
    // minutes later.

So `gbg run collect` reads files the driver is structurally unable to write, and no stage of any
instrument can complete, whatever arguments it is handed.

**A fix that keeps the property the comment wants.** The agents have file tools; the driver already
hands each role its `result_file` path and already builds each brief. Have each reader WRITE its own
result file as the last step of its brief, and let the driver collect only the names of those that
wrote. The collector stays a separate program reading files minutes later, the return value stays
small, and nothing needs a filesystem in the script. Returning the results through the workflow's
value instead would also work, but it is the option that gives up the property the comment was
protecting, and it makes the session the courier for every finding.

**Worth checking the rest of the driver against that sandbox before the next tag**, since this is the
second launch-blocking defect in two candidates and neither could be found by reading Julia. The same
reference also rules out `Date.now()`, `Math.random()` and argless `new Date()` — they throw, because
they would break resume. A grep for those three across `drivers/` costs nothing and would say whether
a third blocker is waiting behind this one.

**Not worked around here, on the owner's word**, as in §4: PF runs the pinned driver or it does not
run. Run `2026-09-22-documentation-review-02` stays open at `find` with nothing launched.
