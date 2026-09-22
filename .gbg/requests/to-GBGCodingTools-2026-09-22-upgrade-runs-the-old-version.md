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
