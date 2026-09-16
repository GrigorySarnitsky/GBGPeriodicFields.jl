# Multi-GPU and memory-spill proposal (2026-09-16) — how it was produced

The deliverable is `DESIGN.md` beside this file: a proposal, **not a decision and not code**. It overturns
a recorded scope (`docs/ARCHITECTURE.md` §1, `docs/PERFORMANCE.md` §1, decision 37), so it waits on the
owner's ruling. Read `DESIGN.md` §0 first — it lists what the adversarial pass reversed.

Provenance, in reading order:

- `00-frame.md` — the decision points any such design must answer.
- `01-hardware-facts.md` — NAISS Arrhenius, the bandwidth ladder, the capacity ladder (web-sourced).
- `05-ecosystem-facts.md` — the Julia distributed-FFT and unified-memory landscape, with the maturity
  findings that decided against taking a dependency.
- `03-code-facts.md` — a `file:line` inventory of every single-process/single-device assumption in the
  package, from two inventory passes over `src/`, `ext/`, `test/`, `benchmark/` and the consumer.
- `02-cost-model-draft.md` — order-of-magnitude arithmetic. ESTIMATE throughout; nothing was measured.
- `DESIGN.md` — the proposal (revision 2).
- `REVIEW-hpc.md`, `REVIEW-invariants.md`, `REVIEW-consumer.md` — three adversarial reviews of revision 1,
  from the HPC, package-invariant and consumer lenses.
- `07-revision-rulings.md` — the rulings that resolved them.
- `08-verified-by-me.md` — the six claims the session checked first-hand against the source, rather than
  taking on report. They include the two that reversed the central design choice.

Nothing in the package was changed. Six live defects the work uncovered are listed in `DESIGN.md` §0;
they are worth fixing whatever the owner decides about multi-GPU.
