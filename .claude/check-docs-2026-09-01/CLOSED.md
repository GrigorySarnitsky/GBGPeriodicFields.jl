# /check-docs round CLOSED — 2026-09-01

18 findings banked across 11 lanes; **18 closed** (17 fixed, 1 dismissed with reason). Five
verification rounds. Build exits 0, `guards.sh` exits 0, `doi_crosscheck` 0 missing, `argcov` 0
candidates, `HIST_CPU.jl --smoke` green with Parseval exact.

## Why this round is closed rather than looped again

Round 5 graded 18/18 and returned **six LINE-ONLY, every one a mechanical demotion and none
substantive**. Each carries the `[DEMOTED: HONORED claimed with no enumerated class surface]` marker,
and each one's own evidence independently re-verifies its class clean by corpus grep. That is the
demotion artifact CLAUDE.md already records — the rule "misfired on notation, demanding `file:line`
and a fixed vocabulary", demoting graders who answer a class with "no remaining instance" instead of
a list. A grader who has swept a class to zero has no `file:line` list to give, so a fully-closed
finding demotes by construction and a sixth round would re-derive the same six.

The substantive series across rounds is what converged:

| round | graded | substantive LINE-ONLY | what it caught |
|---|--:|--:|---|
| 1 | 9 | 1 | the `L` glyph class: 5 sites named, 3 fixed |
| 2 | 18 | 1 | the interpunct class: a survivor in a rendered docstring |
| 3 | 18 | 1 | the sentence-opener class: never scanned on doc pages at all |
| 4 | 18 | 2 | the same class again — my own scan pattern too narrow; plus one dismissal |
| 5 | 18 | **0** | nothing |

Round 1's 9-of-18 was itself a finding: `coverage.py` showed the pile was banked 0-indexed while the
instrument resolves 1-indexed, so half the findings were never graded behind an 89% rate.

## The dismissal

**`src/DifferentialOperators.jl:576`** — a fourth restatement of decision 77's formula carrying
``\mathrm{i}\,a``, in a plain `#` comment. Not a defect: CLAUDE.md exempts `#` comments from the
rendering rules twice (the check-docs surface list, and §Style's "plain `#` code comments stay
Unicode — they are not rendered"), and the thin-space rule governs rendered math spacing. Consistent
with fixing the examples' `##` comments for the `L` collision: a symbol meaning two things is a
comprehension defect a code reader meets regardless of rendering, while a gratuitous thin space in an
unrendered line has no reader-visible effect. Semantic defects reach into comments; typographic ones
do not.

## Coverage — read with the judgment the gate defers

`coverage.py` reports 7 lanes `ok` (13 findings, 13 verdicts) and **4 lanes at 0/0**, which it flags
because it cannot tell a clean lane from a dead one and correctly refuses to guess. Those four are
`04-performance`, `06-src-ops`, `09-family`, `10-cold-reader`, and they are CLEAN, not dead: each
banked a substantial enumeration of what it checked (7.4 KB, 14 KB, 12 KB, 8.0 KB respectively) — the
performance lane re-checked every (ak)/(al) figure against `RESULTS.md`, `src-ops` read five files end
to end, the family lane enumerated 39 operation families, and the cold-reader lane covered every
exported docstring. A dead lane produces nothing; these produced their working.

One parse collision was fixed rather than argued: `06-src-ops.md` headed its six CHECK sections
`## 1. CORRECT …`, which `coverage.py`'s `^#{2,4} +(?:Finding +)?(\d+)` reads as six banked findings,
making the lane report SHORT by six. Renamed to `### Check 1 — …` so the headings cannot parse as
findings.

## Instrument findings — reported, NOT silently patched

Instruments are frozen; a change to one is its own deliberate commit. Two were surfaced by this round
and are left for that:

1. **`guards.sh:77` scans `src/*.jl` only** for the sentence-opener class, while the command's own
   readable source-of-truth spells the same scan `... src/*.jl $DOCS_MD`. The script is narrower than
   its spec, so the doc pages had never been scanned for that rule — and its "ok" was read as
   coverage, by me, in round 1. A check narrower than it appears is worse than an absent one. Fixing
   it would have found the 22 doc-page violations this round fixed by hand.
2. **The demotion predicate misfires on a fully-swept class** (see above). Recorded because a column
   that reports six spurious demotions is a column that stops being read, which is the failure mode
   CLAUDE.md names: "a check nobody reads passes everything."
