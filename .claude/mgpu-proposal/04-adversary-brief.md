# Brief for an adversarial reviewer of the multi-GPU + spill design

Read, in this directory: `DESIGN.md` (the proposal under attack), `00-frame.md` (the decision points it must
answer), `01-hardware-facts.md`, `02-cost-model-draft.md`, `03-code-facts.md` (a file:line inventory of the
package, from two inventory agents). The package is at
"/home/grigory/Dropbox/Research and Teach/Isotropic Turbulence/GBGPeriodicFields" — read its `CLAUDE.md`
(the fourteen invariants, the definition of done, the consent gate) and any source you need; read-only, change nothing.

Your job is to break the design, from your assigned lens. For every attack, give a CONCRETE scenario — a
specific operation, grid, rank count, field and sequence of calls — and say whether the design as written
defeats it, citing the section. Verdicts: DEFEATED / BREAKS / UNPROVEN (the design neither defeats it nor
admits it). For each BREAKS or UNPROVEN, give the minimal repair.

Attack at least these, and add your own:
1. A silently wrong answer: any operation that under the proposed decomposition returns a plausible number
   that is not the right one (the zero mode, the reality pairing, the wrap in the transfer kernels,
   a normalization that stayed local, a shell count that differs between ranks).
2. A deadlock or a hang: a legitimate consumer program that stops making progress.
3. An invariant the design amends without saying so, or amends wrongly (9 ownership, 13 allocation-free,
   14 storage family and precision, 4 the zero-mode scaling, 3 fiber-last layout, 6 no scalar indexing,
   11 the transform input contract, 12 no time/particles, and the bitwise thread-count invariance guarantee).
4. A performance claim in the design that the evidence does not support, or that is contradicted by the
   package's own recorded findings (`docs/PERFORMANCE.md`).
5. The staging: a stage whose "definition of done" cannot be verified with the hardware the owner actually
   has (one AMD workstation, one NVIDIA workstation, no cluster access yet), or a stage that strands the
   next one.
6. The user-friendliness claim: find the place where a consumer must know something the design says it
   need not, and the place where the design's "one line changes" is false.
7. The dependency and portability story: what happens on the AMD home box, on the office NVIDIA box, in CI,
   and on aarch64; what happens if the chosen distributed-FFT provider is unmaintained, lacks a feature,
   or is slower than the vendor library on the production machine.
8. Test integrity: the oracle problem (decision 55 forbids leaning only on a 1-rank-vs-4-rank comparison),
   the frozen ledgers (method parity 206/122, the pass audit's traffic counts, the allocation rows), and
   what a green suite would still fail to prove.
9. The honest alternative: is there a cheaper design that gets most of the value, and does the proposal
   compare itself to it fairly? Is there a case for doing nothing, or only feature A?

Write your report to the output path you are given: numbered attacks, verdicts, repairs, then a ranked list
of the five most consequential problems and the residual risks the owner must accept. Terse, no praise,
no restatement of the design. ≤ 250 lines.
