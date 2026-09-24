# Triage of the first documentation review (2026-09-22)

Moved here from `.claude/WORK_QUEUE.md` on 2026-09-24, at the owner's word, because from
GBGCodingTools rc.17 every review close rewrites that file's `## From the last review` section whole,
and this was the only record of the triage. Nothing counts this file.

**Read the numbers below as a record, not as a work list.** Each finding id (`018`, `140`, …) named a
finding whose full text, locations and proposed fix lived in the run's scratch area, and that area was
deleted when the run was abandoned. The report the body below points to never held them: it said
"Nothing was found" and was removed in `9c8a555b`. The next review reads everything afresh and carries
none of these, so anything still wrong will be found again with its text.

What survives with enough detail to act on:
- `004` — `examples/HIST_CPU.jl` calls ``u \times \omega`` the Lamb vector, where the name denotes
  ``\omega \times u``. A real error, and a formula edit, so it goes to the owner.
- `014` — over-wide code lines in `examples/HIST_CPU.jl`; the owner granted the wrap as a code change
  on 2026-09-24.
- The two withdrawn fixes — the tutorial's fiber-last shapes and the `FiberSections` module-map
  bindings — wait for a deliberate re-baseline of `docs/prose_shape.csv`.

The triage as it stood, unchanged:

Run `2026-09-22-documentation-review-01`, 2026-09-22, bound readers over 23 built pages. It found 142
defects; 22 are fixed and committed, and the run was abandoned at its verify stage because the
verifier arguments reach 744 KB and the driver takes them only inline. These are the owner's list.
The record and report are in `.gbg/runs/2026-09-22-documentation-review-01/`.

**Disregarded, not defects here (17).** Findings against `docs/src/gbg-*.md`, which are generated
pages this package declares in `generated`; the run's per-page walk read them anyway, which
GBGCodingTools is fixing. A page that states the rules quotes every banned spelling in order to ban it.

**Waiting on a scoping switch (15).** `RULE.DOC.TERMS_DEFINED` and `RULE.DOC.SELF_CONTAINED` against
the rationale documents other than `ARCHITECTURE.md`. Satisfying them means re-binding *fiber*,
*section* and *base* on every page, against this package's own one-concept-one-home rule. The switch
is agreed and lands outside a run.

**Blocked on the tool, raisable but not fixable (4).** `014` and `004` sit in `examples/HIST_CPU.jl`,
which the guard does not list as a place documentation lives, so no documentation fix may touch it —
`004` is a real error, the example naming `u × ω` the Lamb vector when that name denotes `ω × u`.
`033` is two docstrings on a bare binding, whose text the guard reads as program text. `011` asks for
a `Switch`, which is a config change and cannot happen inside a run.

**Deliberately withdrawn, needing a prose re-baseline (2).** The tutorial's fiber-last shapes and the
`FiberSections` module-map bindings both add information no rewording returns; `RULE.DOC.SHAPE` holds
their units at their recorded size. Re-baseline deliberately, with the reason, then re-apply.

**Not examined (88).** Grouped by the rule that raised each.

- [ ] **TERMS_DEFINED** (30): 018, 024, 032, 034, 039, 041, 042, 045, 046, 047, 048, 055, 056, 060, 061, 062, 063, 068, 070, 079, 087, 105, 106, 109, 114, 115, 121, 138, 139, 140
- [ ] **SELF_CONTAINED** (20): 017, 028, 029, 031, 035, 043, 051, 064, 065, 067, 069, 071, 080, 085, 107, 111, 116, 117, 131, 141
- [ ] **GRAMMAR** (17): 057, 059, 066, 072, 078, 082, 083, 108, 110, 112, 113, 125, 126, 128, 129, 130, 137
- [ ] **RETURNS** (6): 026, 030, 037, 054, 058, 081
- [ ] **open reader, no rule** (3): 002, 004, 040 — the differential geometer's own findings
- [ ] **ONE_NOTATION** (2): 003, 010
- [ ] **NO_HSCROLL** (2): 014, 015
- [ ] **CODE_SPAN_JULIA** (2): 038, 127
- [ ] **STEER** (1): 005
- [ ] **ONE_HOME** (1): 006
- [ ] **TWO_TIER** (1): 008
- [ ] **VERIFIED** (1): 009
- [ ] **POSITIONAL** (1): 011
- [ ] **LEADING_IDENTITY** (1): 013

The full text of every finding, with its locations and proposed fix, is in the run's report.
