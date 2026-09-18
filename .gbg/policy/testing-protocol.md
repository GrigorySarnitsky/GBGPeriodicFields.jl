<!-- gbg:managed begin v2.0.0-rc.4 — rewritten by `gbg sync`; do not edit -->
# Testing protocol — `RULE.TEST.*`

What a test is for, where its oracle comes from, and when a thing is done. 12 rules, written from the rule values themselves,
so a rule reworded here was reworded in the program that checks it.

### RULE.TEST.ALLOC_ZERO
Every in-place ! operator is allocation-free and in the audit; a deliberate materializer gets a bounded guard; where a bound covers another nondeterminism a configuration pins the true zero.

The audit runs on the CPU, where a materialized temporary is visible; the completeness of its rows is derived from the export list, never remembered.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:TestHarness.allocation_completeness enforces it inside a package's own test suite

### RULE.TEST.BOTH_DIRECTIONS
Test the check in both directions; a check that cannot fail is not a check; a self-reported field is acceptable only when the missing case is the failing case.

The flattering direction is the one nobody guards: a check that demotes sound answers is stopped being read, and a check nobody reads passes everything.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.TEST.COUNTS_REMEASURED
A count nothing asserts is re-measured, never cited; a drop is a finding.

A test count, a testset count, a coverage figure — each is measured at the time it is stated.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: test:test/schemas.jl enforces it inside a package's own test suite

### RULE.TEST.DEFINITION_OF_DONE
A feature is done when its correctness tests, performance test, four guiding docs, remaining docs, benchmarks (built AND run) and examples (run) are each verified.

'Should work' is not done: a step is done when its verification command exits 0 and the exit code was observed. Grep the docs for stale deferred, none-exist and future claims about whatever was just …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.TEST.EXAMPLES_RUN
Shipped examples are executed after any public-surface change; nothing else runs them.

An example is both a rendered page and a downloadable script; the docs build renders it without running it, and a call that no longer dispatches is found only by running it.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:makedocs enforces it inside a package's own test suite

### RULE.TEST.GATE_VS_SURVEY
Pkg.test() is a gate; the exhaustive suite is a survey; a specific oracle and every completeness guard go in the gate.

A gate re-checks claims already known and must be green or the change does not ship; a survey searches for combinations nobody enumerated and is read, not passed. A universal oracle over a product …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.TEST.METHOD_PARITY
The public method set is frozen per generic and per module; any change moves a number.

The per-module count is derived from ownership over the whole function surface, internals included, so a method defined under a qualified name cannot hide.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:TestHarness.method_parity enforces it inside a package's own test suite

### RULE.TEST.MISSING_IS_FAILING
The missing case is the failing case: derived denominators, absence arms, zero count = dead.

An empty witness directory, an empty ledger, an unparsable status — each fails; 'nothing to check' is not 'all clear'.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.TEST.MUTATION
A symmetric fixture cannot see an asymmetric defect; a self-referential assertion cannot see a shared defect; a stated convention must be falsifiable by its fixture.

Inject the defect and require the suite to catch it; a fixture that cannot reach the broken branch proves nothing about it.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.TEST.ORACLE_INDEPENDENT
Every public value-returning operation is classified in the oracle registry; relational-only coverage is a finding.

The classes are analytic (a closed form derived independently of the package), independent (a direct computation written in the test), property (an invariant that pins the operation without …

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:TestHarness.oracle_registry enforces it inside a package's own test suite

### RULE.TEST.PASS_AUDIT
Every audited operation has a frozen per-array traffic row with a named holder for any gap.

A raised count is a fusion regression unless a new holder justifies it; the frozen values are refrozen in the same commit as the change, with the reason.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: harness:TestHarness.traffic_completeness enforces it inside a package's own test suite

### RULE.TEST.RULE_WITH_CHECK
A rule and its check land in the same commit; a stated rule without a check is a known weakness.

A rule is written by whoever has just fixed an instance, at the moment they are most confident the class is handled — which is precisely when nobody builds the check; afterwards the rule's presence …

Decided by nothing yet. Nothing checks it: the rulebook does not check it: test:test/schemas.jl enforces it inside a package's own test suite

<!-- gbg:managed end -->
