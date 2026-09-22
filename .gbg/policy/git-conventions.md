<!-- gbg:managed begin v2.0.0-rc.8 — rewritten by `gbg sync`; do not edit -->
# Git conventions — `RULE.GIT.*`

What a commit carries, where it goes, and what is never committed. 7 rules, written from the rule values themselves,
so a rule reworded here was reworded in the program that checks it.

### RULE.GIT.BRANCH
The working branch is the one `branch` names, `master` unless the package sets it; a rename is the package's decision.

A rename is a decision about the package, never bundled with a tooling adoption.

Covered by the session, as an instruction: followed while working, checked by nothing. Nothing checks it: an instruction to the session: followed while working, checked by nothing
This package may set `branch`; unset, it is `master`.

### RULE.GIT.CI_MANUAL
CI is manual-only; the matrix runs locally before a commit; docs deploy on push.

Before committing a code change, run the gate locally; a documentation-only change needs a load and the docs build. The docs build is therefore the per-push enforcement point, and the doctor, the hard scans and the gate stay inside it.

Covered by the session, as an instruction: followed while working, checked by nothing. Nothing checks it: an instruction to the session: followed while working, checked by nothing

### RULE.GIT.MANIFEST_TRACKED
Sub-environment manifests are gitignored; a tracked root manifest is a declared deviation.

A stale sub-environment manifest is resolved locally when precompilation breaks; CI resolves its own.

Covered by the session, as an instruction: followed while working, checked by nothing. Nothing checks it: an instruction to the session: followed while working, checked by nothing

### RULE.GIT.NO_SHIMS
The API is not frozen; no backward-compatibility shims.

Errors found later are fixed one by one; architectural soundness is judged on the full picture first.

Covered by the session, as an instruction: followed while working, checked by nothing. Nothing checks it: an instruction to the session: followed while working, checked by nothing

### RULE.GIT.PUSH
Commit ⇒ push, directly on the configured branch; no feature branches.

The repository is private and synced across machines through GitHub, so work is committed on the default branch and pushed in the same step; GitHub is the cross-machine sync path and the docs site deploys on push. Stage with `git add -u` plus every new file by name, never `-A`.

Covered by the session, as an instruction: followed while working, checked by nothing. Nothing checks it: an instruction to the session: followed while working, checked by nothing

### RULE.GIT.REQUESTS
A cross-package request is a tracked file .gbg/requests/to-<PKG>-<date>-<topic>.md in the requester with a status paragraph on top; a concluded request is deleted.

The requests directory holds what is still awaiting the other package and nothing else.

Covered by the session, as an instruction: followed while working, checked by nothing. Nothing checks it: an instruction to the session: followed while working, checked by nothing

### RULE.GIT.TRAILER
Every commit ends with the versionless 'Co-Authored-By: Anthropic Claude <noreply@anthropic.com>' trailer; never [skip ci].

The trailer names no model version on purpose: the model in use changes often and the versions supersede each other, so a version in the trailer is a fact about the day rather than about the work, and it goes stale in the one place git never lets anyone correct it.

Covered by the session, as an instruction: followed while working, checked by nothing. Nothing checks it: an instruction to the session: followed while working, checked by nothing

<!-- gbg:managed end -->
