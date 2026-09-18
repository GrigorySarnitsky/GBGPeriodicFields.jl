<!-- gbg:managed begin vdev — rewritten by `gbg sync`; do not edit -->
# Git conventions — `RULE.GIT.*`

What a commit carries, where it goes, and what is never committed. 7 rules, written from the rule values themselves,
so a rule reworded here was reworded in the program that checks it.

### RULE.GIT.BRANCH
The working branch is git.branch (master by default; a rename is a consumer decision).

A rename is a decision about the package, never bundled with a tooling adoption.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: doctor:GIT.BRANCH checks the wiring of a package, not its text

### RULE.GIT.CI_MANUAL
CI is manual-only; the matrix runs locally before a commit; docs deploy on push.

Before committing a code change, run the gate locally; a documentation-only change needs a load and the docs build. The docs build is therefore the per-push enforcement point, and the doctor, the …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.GIT.MANIFEST_TRACKED
Sub-environment manifests are gitignored; a tracked root manifest is a declared deviation.

A stale sub-environment manifest is resolved locally when precompilation breaks; CI resolves its own.

Decided by nothing yet. Nothing checks it: the rulebook does not check it: doctor:WIRE.GITIGNORE checks the wiring of a package, not its text

### RULE.GIT.NO_SHIMS
The API is not frozen; no backward-compatibility shims.

Errors found later are fixed one by one; architectural soundness is judged on the full picture first.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.GIT.PUSH
Commit ⇒ push, directly on the configured branch; no feature branches.

The repository is private and synced across machines through GitHub, so work is committed on the default branch and pushed in the same step; GitHub is the cross-machine sync path and the docs site …

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.GIT.REQUESTS
A cross-package request is a tracked file .gbg/requests/to-<PKG>-<date>-<topic>.md in the requester with a status paragraph on top; a concluded request is deleted.

The requests directory holds what is still awaiting the other package and nothing else.

Decided by nothing yet. Nothing checks it: no program decides it yet: it is a habit the rulebook states and a reader keeps

### RULE.GIT.TRAILER
Every commit ends with the versionless 'Co-Authored-By: Anthropic Claude <noreply@anthropic.com>' trailer; never [skip ci].

The trailer names no model version on purpose: the model in use changes often and the versions supersede each other, so a version in the trailer is a fact about the day rather than about the work, …

Decided by nothing yet. Nothing checks it: the rulebook does not check it: doctor:GIT.TRAILER checks the wiring of a package, not its text

<!-- gbg:managed end -->
