<!-- gbg:managed begin v2.0.0-rc.4 — rewritten by `gbg sync`; do not edit -->
# Instruments — `RULE.INST.*`

How a review runs: consent, witnesses, closure, cost, and the limits it must state. 13 rules, written from the rule values themselves,
so a rule reworded here was reworded in the program that checks it.

### RULE.INST.AUDIT_AFTER_CODE
A fix pass that changed code is audited before its round closes — always for a hunt, and for a check-docs round whose pass touched src or ext — by an audit that read the round's last code change.

`/bug-hunt` always qualifies, and so does a `/check-docs` round whose pass touched the `src` or `ext` surfaces: closing refuses until a `/audit-changes` round based at the closing round's opening …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.AUDIT_DISPOSED
An audit round is closed by disposing its concerns, never by correcting them inside it; a correction rides the next change set, which the next audit covers.

A correction moves the tree, the staleness check then refuses the close, and there is no re-bank; the round would be permanently unclosable. Each gated concern takes a disposition record instead, …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.CARRY
A round may close by carrying a finding into the next round of its instrument — a minor or nit at will, anything still open once its pass budget is spent — on a re-rated severity; it is re-banked there, never rediscovered. A round refuses to close by carrying a finding already carried CARRY_LIMIT (3) times — the owner rules on it instead — and a final release refuses while a carried blocker or major stands, while anything has been carried CARRY_LIMIT times, or while the backlog is not draining.

The budget is `max_passes` verification passes, 3 by default: every pass re-runs both verifiers, and past the third 2026-09-10-check-docs-03 spent six more re-verif

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.CLOSURE_LOOP
The closure loop runs over the banked findings by id, never by re-running the battery; abandon is the only wholesale exit and names every open id.

Closing a banked round terminates because the denominator is fixed; re-running the lanes over a just-edited corpus is a new search with no fixed point. Stop on a plateau — three passes flat within …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.CONSENT
Unasked, run only Pkg.test(); every instrument, survey, benchmark and panel runs only on the user's request, in words or by slash.

The correct output when one would be informative is to name it and its cost and wait. This is a consent boundary, not licence to leave work unfinished: finish the code, run the gate, and report what …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.ECONOMY
Economy lanes by default; the five never-economised phases; strength = full on explicit request.

A cheap lane's false positive is caught downstream; a false negative in a lane with no downstream verifier is why some lanes are anchors and stay at full strength in every mode.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.FIX_FROM_LANES
A fix pass is driven from the per-lane findings by id, never from the consolidated summary.

Consolidation is lossy by design, which is what makes it readable; a severity in the summary never overrides the lane's own, and closure is reported per lane and per id.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.FOUR_OBJECTS
The four instruments audit different objects: changes, source prose, rendered prose, code.

A flawless docstring on a function returning the wrong number passes both prose instruments; an edit that is a correct fix and still wider than the defect passes the hunt; each exists for what the …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.FROZEN_MIDROUND
An instrument is never changed mid-round; a change is its own commit and release; a deferral is written in the round's deferred.md and carried into the work queue at close; a round whose own frozen verifiers or auditors cannot run has those differing copies replaced by gbg round scripts --reason, never a lens, recorded in ROUND.toml.

A change the round wanted and could not make is written one line per deferral in the round's `deferred.md`, and `gbg round close` carries each into `.claude/WORK_QUEUE.md`, where the Stop hook holds …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.NO_TRUNCATION
A scan output is never truncated (head, tail, a limit); count first, then read all.

Adding a limit to keep the output readable is how a class gets half-swept and reported closed; a deterministic check that depends on who types it is not deterministic.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:report enforces it inside a package's own test suite

### RULE.INST.SEEDS
A seeded finding is never fixed in the corpus and never enters the ledger.

Seeds are planted in a disposable copy to measure recall; the ground truth reaches no hat; a class at zero seeded recall is unmeasured, not clean; and recording a seed as adjudicated would hand the …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.SELF_REPORT
Self-reported closure is not closure; the act verifier sees the diff, the state verifier is blind; the demotion is mechanical.

Both default to the unfavourable verdict so a truncated lane fails safe; a zero count is a dead lane rather than a clean hat; the denominator never comes from the party being measured; and a …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.INST.WITNESS
A static claim about code is a hypothesis; the only evidence is a program that fails; a fixed witness is promoted unchanged.

A passing witness means not a bug, discarded however good the argument; no witness writable means a latent hazard, reported and not fixed; a failing witness is the finding and, once the fix lands, …

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:Witnesses.run enforces it inside a package's own test suite

<!-- gbg:managed end -->
