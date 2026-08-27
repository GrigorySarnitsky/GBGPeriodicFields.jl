---
description: Audit a change set — was each edit justified, and did it silently alter behaviour that worked before?
---

# /audit-changes — were these edits justified, and did they silently change behaviour?

The fourth instrument. `/check-docs` and `/check-consistency` audit **prose**; `/bug-hunt` audits
**code**. This one audits **changes to code** — a different object, with failure modes none of the
others can see. Run it after any instrument's fix pass, or on request over any commit range.

## The question, and why it is not a defect hunt

> **Was each change proportionate to the defect it claims to fix, and did it silently alter behaviour
> for input that previously worked?**

An edit can be a *correct fix* and still be wrong to make: wider than the defect required, changing a
default, rejecting a workflow that used to be legitimate, breaking a contract the fix did not need to
touch. Neither the code nor the fix looks wrong in isolation, which is exactly why a hunt cannot find
it — **a hunt reads code; this reads the diff.**

A finding that would have been true *before* the diff belongs to `/bug-hunt`, not here.

## Why the witness gate does not cover this

`/bug-hunt` ends with `witnesses.jl`, which proves every confirmed finding behaves as claimed. IT
measured that gate against a real change set: it reported **`NEWLY BROKEN = 0` while two regressions
were live** and confirmed by hand. A witness exists only for a defect the hunt *found*, so **a
regression introduced by a fix is invisible to it**. PF has the same hole — `test/regressions/` holds
witnesses for found defects and nothing else. That gap is this tool.

## Running it

```bash
git diff <base>..HEAD -- src test docs > /tmp/changes.diff
git log --format="%h %s" <base>..HEAD    > /tmp/claims.txt      # optional
```

```
Workflow scriptPath=".claude/commands/audit-changes/audit.js" \
  args='{"repo":"<abs>","diff":"/tmp/changes.diff","claims":"/tmp/claims.txt","strength":"economy"}'
```

Then record the audit and its dispositions as `.claude/audit-changes/latest.json` and gate it:

```
python3 .claude/commands/audit-changes/gate.py
```

## The lanes, and the two that carry the design

Ten lanes, differing by **lens**, not by checklist. Four are anchors and are never economized.

- **`executing`** — the one that keeps the instrument honest. Every other lane *reads*, and that is
  this design's central flaw: the instruments these edits come from are founded on *"a static claim
  about code is a hypothesis; the only admissible evidence is a program that fails"* — and the audit
  of them was built out of readers. So an edit justified by a measurement written in a comment
  (*"allocates nothing"*, *"bitwise-identical"*, *"2.7–6.5×"*) would be certified by an agent that read
  the comment. This lane **runs** them, and PF is unusually good for it because its claims are
  executable: `Pkg.test()`, `test/allocations.jl`, `test/pass_audit.jl`, `test/method_parity.jl`.
- **`under-rejection`** — guards the diff **removes or weakens**. Its dual has an obvious symptom: an
  over-strict guard throws in your face. A *removed* guard returns a wrong number instead.
- `free-reader` (no list at all, because a list is a hypothesis about where the problems are),
  `over-rejection`, `behaviour-change`, `invariants` (PF's numbered ones), `backend-portability`
  (CPU-identical, device-broken — the gate runs only on `Array`), `claim-versus-edit`,
  `contract-drift`, `sweep-completeness`.

## The disposition gate

`gate.py` asks the two questions a program can answer: **has every serious finding been *answered*** —
fixed, refused *with a reason*, or escalated, but **not absent** — and **does the audit still describe
the tree**. It carries no adversarial verifier by design: the audit already has its mechanical anchor
in the `executing` lane, and auditing the auditor is where the regress begins.

Two things it does that are not obvious. A concern naming input that **previously worked** is treated
as serious whatever the lane called it — that field is what the instrument exists to surface, so its
severity is not the reporting lane's to downgrade. And an audit whose recorded commit is **unreachable**
fails as `UNCHECKABLE` rather than passing: `git diff` against a rebased-away commit prints nothing,
and empty output is indistinguishable from "nothing changed". That inversion made a stale audit pass
when this gate was first falsified — the safest-looking outcome arriving exactly when the audit cannot
be checked at all.
