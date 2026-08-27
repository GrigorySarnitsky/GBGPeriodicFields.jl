# /bug-hunt — the code instrument

`/check-docs` and `/check-consistency` both audit **prose**. Neither asks whether the code is
*correct*. A docstring can be flawless about a function that returns the wrong number and both
instruments will pass it clean. This one hunts the code.

## The one rule

> **A static claim about code is a hypothesis. The only admissible evidence is a program that FAILS.**

This is a correction for a measured failure mode, not a preference. An agent reading code and
reporting what "looks wrong" produces fluent, confident, unfalsifiable prose. In a documentation
instrument that costs a wasted read. Here it costs **a fix pass on working code** — strictly worse
than the imagined bug, because the tree gets edited, the suite still passes, and afterwards nobody
can tell whether anything was ever wrong.

So the hunt is **static** and the confirmation is **dynamic**. Every candidate is reduced to a
**witness**: a self-contained `@testset` asserting the *correct* behaviour, therefore observed to
**fail** on the current tree.

| outcome | meaning |
|---|---|
| witness **fails** | the finding. Unchanged, it is the regression test the fix must flip. |
| witness **passes** | **not a bug.** Discarded, however good the argument. |
| witness **errors** | evidence about the witness, not the package. Fix it and re-run. |
| **no witness writable** | a latent hazard: reported, never fixed on that evidence. |

A failing witness is **necessary and not sufficient**, which is why adjudication is a separate phase:
a witness can fail because the *witness* is wrong, and a test asserting a false identity fails on
perfectly correct code. An independent lane must derive the correct behaviour from an oracle before a
candidate becomes a finding.

## Why PF suits this better than its origin does

The rule needs an **oracle** — something that says what the answer must be, independently of the code.
PF's operations carry exact mathematical contracts, so one is usually available: adjointness
(`M·⟨Wf,q⟩ = N·⟨f,Wᵀq⟩`), Parseval, `sum(spectrum) == C(0) == inner`, `div(curl) = 0`, the
forward-unnormalized / inverse-normalized FFT convention, the exact idempotence of the discrete
projector, bit-for-bit agreement between a compressed kernel and its materialized form. Where an
oracle exists a witness is usually writable, which is exactly where this instrument has teeth.

It also has a natural relative already in the tree. Decision 52's **mutation audit** is this rule's
*dual*: it injects a defect and requires the suite to catch it, where the witness rule claims a defect
and requires a failing test. Decision 55's **oracle registry** already refuses a claim of coverage
that rests only on the package's own other paths. This instrument is the third member of that family.

## Lanes are free, not class-bound

Lanes differ by **territory** (which files) so coverage spreads, and are otherwise unconstrained. They
run **in parallel**, which forces one rule: every witness filename is prefixed with its lane key. An
unprefixed name can collide with another lane's, and a collision here is not a lost file — it is one
lane overwriting a witness while another is running it, yielding a verdict about the wrong program. IT
measured unconstrained readers beating eight defect-class lanes at a third of the cost, and catching
four regressions it had introduced itself. A class list is a hypothesis the instrument then reports
`complete` over — a false comfort, and worse than no list.

## Running it

```
Workflow scriptPath=".claude/commands/bug-hunt/hunt.js" \
  args='{"repo":"<abs repo root>","pile":"<abs scratch dir>","strength":"economy"}'
```

`strength` defaults to `economy` (cheap hunt lanes; adjudication is never economized, because a cheap
lane's false positive is caught downstream while a cheap adjudicator's false negative has no
downstream check). **This is an opt-in, consent-gated instrument** like the panel and the survey: it
spends real tokens and it runs Julia repeatedly. Do not launch it unasked.

## What to do with the output

- **CONFIRMED** — the witness is the finding. Promote it into `test/regressions/` **unchanged**, then
  fix. A witness edited to suit the fix has stopped being evidence.
- **WITNESS-WRONG / NOT-REPRODUCED / ALREADY-COVERED** — dismissed. Record the dismissal reason; do not
  quietly re-open it next round.
- **Latent hazards** (no witness) — recorded, not fixed. If one recurs across rounds it is worth the
  work of building an oracle for it, and that is the moment to do so, not before.

## What it is not

It is not a linter, and it is not a substitute for the suite. A defect `Pkg.test()` already catches is
not a finding here — the target is what the suite passes over. It never edits `src/`, `test/` or
`docs/`; hunt lanes write witnesses into the pile and nothing else.
