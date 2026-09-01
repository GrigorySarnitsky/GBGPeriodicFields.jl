# Round CLOSED — 2026-09-01

The 2026-08-27 `/check-docs` round banked here. It reported **8 findings open across 5 lanes** and
had failed `lint_review_closure()` — and therefore every `docs/make.jl` run — from that date until
today. It is closed now, on its merits, and this file records how.

**Seven of the eight were never open.** They were spurious demotions produced by a stale predicate,
not by unfinished work.

`lint_review_closure()` counts a finding closed only if its verdict is `HONORED` *and* its
`class_surfaces` answer satisfies a predicate. That predicate is, by its own comment, "deliberately a
TWIN of the predicate in `check-consistency/verify-fixes.js` — edit the two together". On 2026-09-01
the verifier's copy was patched (user-directed) from matching a **fixed vocabulary**
(`site|surface|instance` plus a short phrase list) to testing whether a **substantive class answer was
given** — because the vocabulary form demoted every sound answer that used a synonym, measured at six
spurious demotions out of six in one round. **The twin here was not edited with it**, so the lint went
on applying the retired predicate for a day.

Measured over this round's own verdict files: **30 `HONORED` verdicts; the old predicate passes 23,
the patched predicate passes 30.** The seven-verdict gap plus the one genuinely open finding is
exactly the eight the lint reported. The twin is now synced, and that sync — not this file — is the
durable fix.

**The eighth was real and is fixed.** `03-docstrings-A` Finding 3: formula-like pseudo-code in
backticks in the FiberSections codegen builders. `src/FiberSections.jl:490` wrote
``destination_i .= formula(i)`` in a code span, where `destination_i` is not an identifier the code
has — the real target is `_vector_component_data(destination, i)` — and `:802` wrote
``α * f(element values..., constants...)``, which is mathematics rather than Julia. Both are rewritten.
Sweeping the class rather than the two quoted lines found a **third site the finding did not name**,
`:523`, the tensor twin `_tensor_kernel_body` carrying the identical `destination_ij .= formula(i, j)`;
it is fixed too. A package-wide re-scan leaves no pseudo-identifier inside a code span in `src/`.

**Why this file exists rather than a re-verification.** With the twin synced and the eighth finding
fixed, the lint's remaining objection is its "one round, one sitting" coherence rule: this round's
verdict files now span 2026-08-27 and 2026-09-01, because one lane was closed today. That rule is
right and stays — a lane whose verdicts predate its findings did not re-run. The two ways past it were
to re-verify all eight lanes against a five-day commit range, which would grade today's work as if it
were that round's, or to record the account here. **Touching the other seven files' mtimes to make the
round look like one sitting was not an option** — that is falsifying the evidence a check reads, which
is the failure mode this whole apparatus exists to prevent.

**Account:** the 8 findings, their per-lane verdicts, and the predicate measurement are in this
directory (`NN-*.md` and `closure/NN-*.md`); the fix and the twin sync are in the 2026-09-01 commits
touching `docs/make.jl` and `src/FiberSections.jl`.
