# Triage of the first documentation review (2026-09-22)

Moved here from `.claude/WORK_QUEUE.md` on 2026-09-24, at the owner's word, because from
GBGCodingTools rc.17 every review close rewrites that file's `## From the last review` section whole,
and this was the only record of the triage. Nothing counts this file.

**Every finding's full text is at the end of this file**, under "Every finding, with its full text". The texts lived in the run's scratch area, deleted when the run was abandoned; the owner restored it from Dropbox on 2026-09-24. The report the triage below points to never held them: it said "Nothing was found" and was removed in `9c8a555b`. The next review reads everything afresh and carries none of these.

**The triage's counts do not all match the commits.** Counted from the `GBG-Docfix-Finding` trailers, 18 findings are fixed and 3 withdrawn (21 touched), where the triage and commit `822d1994` say 22 fixed; and 16 findings sit only on a generated page, where the triage says 17. The per-finding statuses at the end are the derived ones.

Worth knowing without reading the list:
- `004` — `examples/HIST_CPU.jl` calls ``u \times \omega`` the Lamb vector, where the name denotes
  ``\omega \times u``. A real error, and a formula edit, so it goes to the owner.
- `014` — over-wide code lines. `examples/HIST_CPU.jl` is wrapped (2f225a9c, granted by the owner as a
  code change on 2026-09-24); three lines in `docs/src/tutorial.md` remain.
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

## Every finding, with its full text

Restored on 2026-09-24 from the run's `4-fix/findings.json`, which the owner recovered from Dropbox's deleted files. The status of each is derived from the `GBG-Docfix-Finding` trailers in `git log c6bd2695..HEAD`, not from the triage above. 105 open, 3 withdrawn, 16 disregarded, 18 fixed. Line numbers are as of the run's commit, `c6bd2695`.

### Open (105)

#### 011 — RULE.API.POSITIONAL

*Status:* open.

*Claim.* Three public entry points take a keyword argument that changes the result, and .gbg/config.jl declares no Switch on this rule for any of them: `corrected` on var, std and cov decides whether the moment is divided by the count or by the count minus one; `scheme` on the callable field decides which stencil evaluates it; and `origin` on Grid3D's two-argument constructor shifts every node. Each has a recorded reason in CLAUDE.md — matching Statistics' spelling, a one-point convenience, and the churn of changing a constructor — but the rulebook says an exception to this rule is a Switch with its reason, and a reader of .gbg/policy/ has no way to learn that these three were weighed.

*Proposed fix.* Declare one Switch on RULE.API.POSITIONAL in .gbg/config.jl naming these three sites and the reason for each — `corrected` follows Statistics.var's own signature, the callable's `scheme` was settled 2026-08-05, and Grid3D's `origin` was settled 2026-09-02 against the churn — so that a future review closes against the config rather than re-raising them. Changing any of the three is breaking and is not what this finding asks for.

*Located at:* `src/Fields.jl:184`, `src/Interpolation.jl:1180`, `src/Reductions.jl:650`, `src/Reductions.jl:701`.

#### 033 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Two allocating wrappers state their representation restriction as a verbless fragment standing as its own sentence, where every other entry on the page states the same restriction in a full sentence.

*Proposed fix.* Write both as sentences in the page's own wording, for example 'This form is defined in physical representation only.', and settle on 'physical representation' in both.

*Located at:* `docs/src/api/FieldAlgebra.md`.

#### 057 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Several sentences have no subject and verb: a noun phrase is punctuated as a clause, and a reason is given as a list of fragments.

*Proposed fix.* Restore the verbs: "This is the one family that couples base and fiber", "The function recurses for the same reason as _convert_terms: a specialized tuple goes in and a specialized tuple comes out, and nothing is boxed", "These methods are provided by a package extension".

*Located at:* `docs/src/api/Points.md`.

#### 059 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Three sentences do not stand as sentences: a copula with no complement, a comma splice joining two independent clauses, and a clause missing the word that would join it.

*Proposed fix.* Write "The parts are the following, each linking to…" (or restore the colon); split the splice into two sentences or subordinate one clause; write "…and on the host, whatever backend the field lives on."

*Located at:* `docs/src/api/Reductions.md`, `src/Reductions.jl:1342`, `src/Reductions.jl:19`.

#### 066 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Paragraphs and list items across the page open with a verbless label fragment punctuated as a sentence — a noun phrase, sometimes with a colon or an em-dash appositive, but with no finite verb of its own.

*Proposed fix.* Give each lead-in a verb, or demote it to a real heading: 'Method: the local splines (the physical-domain family).' becomes 'The physical-domain family uses local splines.'; 'Two scheme families (decision 23).' becomes 'Two scheme families share the transfer verbs.'; 'Elementwise/fiberwise ops.' becomes 'Elementwise and fiberwise operations route through one primitive.'

*Located at:* `docs/ARCHITECTURE.md:438`, `docs/ARCHITECTURE.md:656`, `docs/ARCHITECTURE.md:699`, `docs/ARCHITECTURE.md:886`, `docs/ARCHITECTURE.md:910`, `docs/ARCHITECTURE.md:959`, `docs/ARCHITECTURE.md:992`, `docs/src/architecture.md:438`, `docs/src/architecture.md:656`, `docs/src/architecture.md:699`, `docs/src/architecture.md:886`, `docs/src/architecture.md:910`, `docs/src/architecture.md:959`, `docs/src/architecture.md:992`, `docs/src/architecture.md`.

#### 072 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Entries open, and paragraphs continue, with verbless noun-phrase fragments: a label, a colon or a dash, then a list of things, with no finite verb anywhere in the sentence.

*Proposed fix.* Give each entry headline and each in-paragraph lead-in a subject and a finite verb — 'This entry refactors Fields: it adds atomic compatibility predicates …', 'The builder alone ships; there is no fused translate!' — keeping the compactness and restoring the grammar.

*Located at:* `docs/DECISIONS.md:1224`, `docs/DECISIONS.md:32`, `docs/DECISIONS.md:695`, `docs/src/decisions.md:1224`, `docs/src/decisions.md:32`, `docs/src/decisions.md:695`, `docs/src/decisions.md`.

#### 078 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* The narrative blocks that introduce each code section are written as verbless noun phrases and `label:` colon tags rather than sentences, so most of the page's connective prose has no main verb.

*Proposed fix.* Restore the verb in each introductory block: 'These are the preallocated scratch fields the hot loop needs, so a step allocates nothing', 'The setup builds the grid, the transform plans, ...', 'The final diagnostics are the energetics, the Kolmogorov and Taylor scales, ...'. Where a colon tag survives, put a clause on each side of it.

*Located at:* `docs/src/examples/hist_cpu.md:237`, `docs/src/examples/hist_cpu.md:455`, `docs/src/examples/hist_cpu.md:73`, `docs/src/examples/hist_cpu.md`, `examples/HIST_CPU.jl:209`, `examples/HIST_CPU.jl:393`, `examples/HIST_CPU.jl:403`, `examples/HIST_CPU.jl:68`, `examples/gpu/rocm/HIST_ROCm.jl:235`, `examples/gpu/rocm/HIST_ROCm.jl:414`, `examples/gpu/rocm/HIST_ROCm.jl:424`.

#### 082 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Verbless label fragments are used as sentences throughout the page — a noun phrase closed by a full stop, and in nine places a 'label:' colon tag. Each is punctuated as a sentence and none has a verb, so none reads as a sentence aloud.

*Proposed fix.* Give each fragment a subject and a verb: 'The design rationale is in Architecture §11.'; 'The adjoint holds in raw (counting) form.'; 'The kernel is a pure phase away from Nyquist.'; 'Statement 1 is the retraction.'; 'The reductions act on fields in physical representation and on point-values only.'; 'The tests are in test/reductions.jl.'

*Located at:* `docs/FORMALIZATION.md:103`, `docs/FORMALIZATION.md:420`, `docs/FORMALIZATION.md:573`, `docs/FORMALIZATION.md:664`, `docs/FORMALIZATION.md:691`, `docs/FORMALIZATION.md:801`, `docs/src/formalization.md:103`, `docs/src/formalization.md:420`, `docs/src/formalization.md:573`, `docs/src/formalization.md:664`, `docs/src/formalization.md:691`, `docs/src/formalization.md:801`, `docs/src/formalization.md`, `src/Reductions.jl:608`.

#### 083 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Every section closes with sentences that have a verb but no subject — 'Backs …', 'Checked by …', 'Pinned in …', 'Verified in …'. The subject is elided in all 29 of them, so the reader must supply 'This statement' or 'The claim above' before each, and the participial 'Checked by' form has no finite verb at all.

*Proposed fix.* Restore the subject: 'This statement backs Architecture §10 and the Interpolation module docstring.'; 'The test suite checks it in test/adapt.jl — …'; 'test/adjointness.jl pins it.'; 'test/shared_modes.jl verifies it in "the round trip is the identity on the coarse field".'

*Located at:* `docs/src/formalization.md`.

#### 108 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* A verbless fragment stands as a sentence where the simulation recipe hands the reader its two commands.

*Proposed fix.* Give it a verb, in the form the page already uses elsewhere: 'Run both commands from the root of a clone of the repository:'.

*Located at:* `docs/src/gpu.md:164`.

#### 110 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Both catalogue lists on the page — Main components and Documentation structure — are written as a name, a colon and a noun phrase, so not one of their fifteen entries is a sentence; several run to forty words of apposition without ever reaching a verb.

*Proposed fix.* Give each entry a verb, keeping the length: 'FieldAlgebra defines the fiberwise algebra on fields — vector-space operations, scalar actions, ...', 'Fields carries the core types — grids, fields in ...', 'Getting started walks from a Grid3D to a transform, an operator and a reduction.' Where the entry is a link plus a gloss, the gloss is where the verb goes.

*Located at:* `docs/src/index.md`.

#### 112 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Sentences punctuated as sentences have no verb — starting with the page's own opening sentence, which is a noun phrase closed by a full stop, and continuing through the Convention-column entries, which are written as free-standing sentences (capital, full stop, a complete sentence after them) but carry no subject or verb.

*Proposed fix.* Give each one a predicate: 'This page lists the symbols used throughout the docstrings and the design documents, with the code object each one denotes.'; 'The sums run over the N grid points, over the M points, and over the Fourier modes.'; 'The indices are italic and are taken in order.'

*Located at:* `docs/ARCHITECTURE.md:1096`, `docs/ARCHITECTURE.md:475`, `docs/ARCHITECTURE.md:490`, `docs/ARCHITECTURE.md:491`, `docs/ARCHITECTURE.md:894`, `docs/ARCHITECTURE.md:895`, `docs/DECISIONS.md:1015`, `docs/DECISIONS.md:238`, `docs/DECISIONS.md:2955`, `docs/DECISIONS.md:342`, `docs/DECISIONS.md:458`, `docs/DECISIONS.md:520`, `docs/DECISIONS.md:522`, `docs/DECISIONS.md:718`, `docs/DECISIONS.md:768`, `docs/DECISIONS.md:784`, `docs/DECISIONS.md:798`, `docs/FORMALIZATION.md:240`, `docs/FORMALIZATION.md:246`, `docs/FORMALIZATION.md:254`, `docs/FORMALIZATION.md:287`, `docs/FORMALIZATION.md:289`, `docs/FORMALIZATION.md:298`, `docs/FORMALIZATION.md:306`, `docs/FORMALIZATION.md:327`, `docs/FORMALIZATION.md:329`, `docs/FORMALIZATION.md:335`, `docs/FORMALIZATION.md:339`, `docs/FORMALIZATION.md:355`, `docs/FORMALIZATION.md:415`, `docs/FORMALIZATION.md:422`, `docs/FORMALIZATION.md:423`, `docs/FORMALIZATION.md:429`, `docs/FORMALIZATION.md:502`, `docs/FORMALIZATION.md:50`, `docs/FORMALIZATION.md:755`, `docs/FORMALIZATION.md:756`, `docs/FORMALIZATION.md:91`, `docs/FORMALIZATION.md:96`, `docs/FORMALIZATION.md:97`, `docs/TESTING.md:687`, `docs/src/notation.md:12`, `docs/src/notation.md:13`, `docs/src/notation.md:17`, `docs/src/notation.md:3`, `docs/src/notation.md`, `src/Convolution.jl:1909`, `src/Convolution.jl:1914`, `src/DifferentialOperators.jl:1108`, `src/DifferentialOperators.jl:1109`, `src/DifferentialOperators.jl:1115`, `src/DifferentialOperators.jl:1116`, `src/DifferentialOperators.jl:1117`, `src/DifferentialOperators.jl:114`, `src/DifferentialOperators.jl:118`, `src/DifferentialOperators.jl:1191`, `src/DifferentialOperators.jl:1267`, `src/DifferentialOperators.jl:1272`, `src/DifferentialOperators.jl:381`, `src/DifferentialOperators.jl:453`, `src/DifferentialOperators.jl:536`, `src/DifferentialOperators.jl:579`, `src/DifferentialOperators.jl:712`, `src/DifferentialOperators.jl:800`, `src/DifferentialOperators.jl:807`, `src/DifferentialOperators.jl:808`, `src/DifferentialOperators.jl:901`, `src/DifferentialOperators.jl:908`, `src/DifferentialOperators.jl:909`, `src/Fields.jl:1757`, `src/Interpolation.jl:1338`, `src/Interpolation.jl:1339`, `src/Interpolation.jl:1340`, `src/Interpolation.jl:1364`.

#### 113 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* The magnitude row is one 60-word self-referential sentence whose closing clause has no verb, and as it renders it contradicts itself: it says the literal pipe cannot be shown in the cell, then shows a literal pipe and calls that pipe LaTeX's double bar, which a single pipe is not.

*Proposed fix.* Say what the cell needs in two short sentences and name the spellings without trying to display a bare pipe: 'In this table the bars are written \lvert ... \rvert, because a literal pipe is read as a column delimiter. Outside a table the same symbol takes plain single bars; the doubled form is the L2 norm of the next row.'

*Located at:* `docs/ARCHITECTURE.md:393`, `docs/FORMALIZATION.md:596`, `docs/src/notation.md:58`, `docs/src/notation.md:59`, `docs/src/notation.md`.

#### 125 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Sentences are broken: one stops mid-clause and runs into the next, one repeats a word, and two have words run together.

*Proposed fix.* Finish the truncated clause, delete the doubled 'the', and close the two spacing slips.

*Located at:* `docs/PERFORMANCE.md:1196`, `docs/src/performance.md`.

#### 126 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Verbless fragments are punctuated as sentences, several of them as label-colon tags.

*Proposed fix.* Give each a subject and a verb — 'Speed does not change.', 'The CUDA lane is flat.', 'The suite runs at two scales.' — or promote them to headings, where the rule does not reach them.

*Located at:* `docs/PERFORMANCE.md:1075`, `docs/PERFORMANCE.md:1416`, `docs/PERFORMANCE.md:1449`, `docs/PERFORMANCE.md:2472`, `docs/src/performance.md:1075`, `docs/src/performance.md:1416`, `docs/src/performance.md:1449`, `docs/src/performance.md:2472`.

#### 128 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Section and paragraph lead-ins are verbless label fragments standing where a sentence belongs; the page uses the shape as a convention, so it recurs in every section from 3 onward.

*Proposed fix.* Give each lead-in a predicate, or make it a heading rather than a sentence: 'Tolerances are the part that bites.', 'Cover the grid as follows.', 'The rule is this.', 'The status below is honest, so the contract above reads as a target rather than a description.'

*Located at:* `docs/TESTING.md:272`, `docs/TESTING.md:589`, `docs/src/testing.md:272`, `docs/src/testing.md:589`, `docs/src/testing.md`.

#### 129 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* A symbol is substituted for the verb — an arrow or an equals sign carries the predicate — so the sentence has no verb at all.

*Proposed fix.* Write the verb: 'Operators call for an analytic closed form. Representation parity and backend parity call for a trusted CPU reference.' and 'Adding a backend means mirroring rocm/.'

*Located at:* `docs/src/testing.md`.

#### 130 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* Two of the page's largest passages are single colon-led catalogues that run for well over a thousand words each without a finite verb, so neither can be read as prose at all.

*Proposed fix.* Break each catalogue into sentences, one per file or per covered area — 'The file fields.jl covers …. The file fieldalgebra.jl covers ….' — or turn it into a list whose items are themselves sentences.

*Located at:* `docs/TESTING.md:131`, `docs/src/testing.md:131`, `docs/src/testing.md`.

#### 137 — RULE.DOC.GRAMMAR

*Status:* open.

*Claim.* The page opens each of its two framing statements as a verbless fragment: the tour is announced by a noun phrase, and the mental model by a label-colon tag. Both are the first thing a visitor reads.

*Proposed fix.* Restore the grammar without adding words: "This page is a short, runnable tour of the package." and "The mental model, set out on the Architecture page, is this: a field is a real physical object — ...".

*Located at:* `docs/src/tutorial.md:6`, `docs/src/tutorial.md`.

#### 013 — RULE.DOC.LEADING_IDENTITY

*Status:* open.

*Claim.* The three spectral-kernel builders lead with what they construct in spectral representation and never say what the kernel does to the real object, nor that no clean physical form exists. The package's setting for this rule is 'physical meaning', and its sibling builders in the same module honour it — assignment_window opens with the tent cloud a point deposits and translation_kernel with the displaced field f(x - h) — so the omission reads as drift within one module rather than as a considered silence.

*Proposed fix.* Give each of the three one clause of physical meaning before the construction. For spectral_cutoff and spectral_band the honest clause is that the operation is an ideal low-pass or band-pass — it keeps the waves in a range of wavelengths and removes the rest — and that its physical-space kernel is a non-compact periodic sinc, which is why the docstring gives the transfer function instead. For radial_kernel, that the symbol is a filter isotropic in space, acting on each wavelength alike, whose physical form is whatever the caller's sigma implies.

*Located at:* `src/Convolution.jl:1727`, `src/Convolution.jl:1776`, `src/Convolution.jl:345`.

#### 006 — RULE.DOC.ONE_HOME

*Status:* open.

*Claim.* Two generics in Convolution are documented once per method instead of once on the bare binding: `inv` carries four docstrings and `materialize_kernel` four, one per kernel storage class. Neither generic has a home. The predicted drift has already happened — the four `inv` docstrings state the same concept four different ways, three as a formula and one in prose, and the four `materialize_kernel` docstrings give three different cost statements for the same act.

*Proposed fix.* Write one `inv` docstring on a bare binding, stating the reciprocal kernel 1/g-hat once together with the shared no-zeros condition and the fact that the class is preserved; move each class's specifics (a product inverts factorwise, a radial composes the reciprocal with sigma, a separable inverts per axis at O(N), a stored one inverts coefficientwise) into that class's own docstring, linked. Do the same for materialize_kernel, whose single statement is 'evaluate any kernel into a StoredKernel at O(N^3)', with the per-class cost notes moved to the classes.

*Located at:* `src/Convolution.jl:209`, `src/Convolution.jl:230`, `src/Convolution.jl:250`, `src/Convolution.jl:384`, `src/Convolution.jl:435`, `src/Convolution.jl:544`, `src/Convolution.jl:574`, `src/Convolution.jl:614`.

#### 003 — RULE.DOC.ONE_NOTATION

*Status:* open.

*Claim.* The glyph R carries two meanings at once: the tensor order of a section, which is a package-wide type parameter, and the covariance tensor cov(u). Both appear inside the Reductions module docstring and both appear inside FORMALIZATION, whose Declarations block fixes R as the tensor order in its first line.

*Proposed fix.* Yield the local use, as RULE.DOC.ONE_NOTATION prescribes: R is the package-wide tensor order and cannot move, so rename the covariance tensor. The turbulence-standard alternatives are the Reynolds-stress spelling (with the fluctuation product spelled out) or a plain C for the covariance; whichever is chosen, change it in the Reductions module docstring, the cov docstring and FORMALIZATION's Reductions section together.

*Located at:* `docs/FORMALIZATION.md:561`, `src/Reductions.jl:36`, `src/Reductions.jl:44`, `src/Reductions.jl:666`.

#### 010 — RULE.DOC.ONE_NOTATION

*Status:* open.

*Claim.* The glyph R carries three unrelated meanings across the documentation, and E two, with none of the collisions declared. R is the tensor order everywhere — the type parameter, the coverage axis, the supported-surface bound — and is also written for the covariance tensor R_ij and, in the formalization's resolution-verb section, for the extract operator, where E is simultaneously the embed operator and, forty lines earlier in the same document, the energy spectrum E(kappa). The Reductions module docstring carries both meanings of R within one docstring, five bullets apart.

*Proposed fix.* R is the tensor order package-wide and cannot move, so the two local uses yield. Write the covariance tensor as C_ij (or spell it as cov's own entries without a glyph) in src/Reductions.jl, the Reductions module docstring and docs/FORMALIZATION.md. In the formalization's resolution section rename the two operators to something free of both collisions — the docstrings already call them embed and extract, so \mathcal{E} and \mathcal{X}, or a plain iota and its adjoint, would do — and then either add the chosen symbols to the notation page or leave them scoped to that section with a sentence saying so.

*Located at:* `docs/FORMALIZATION.md:627`, `docs/FORMALIZATION.md:772`, `docs/FORMALIZATION.md:792`, `docs/FORMALIZATION.md:816`, `docs/src/notation.md:66`, `src/Reductions.jl:36`, `src/Reductions.jl:44`, `src/Reductions.jl:666`.

#### 026 — RULE.DOC.RETURNS

*Status:* open.

*Claim.* A class of function docstrings never says what the call returns: the identity sentence names only the effect, and no arrow or 'Returns ...' sentence follows.

*Proposed fix.* Add the missing sentence to each: what with_threading gives back from f(), and that the mutating passes return their destination (or nothing).

*Located at:* `docs/src/api/FiberSections.md`, `src/FiberSections.jl:802`, `src/FiberSections.jl:99`.

#### 030 — RULE.DOC.RETURNS

*Status:* open.

*Claim.* map! is a mutator whose signature carries no arrow and whose docstring never says what it returns; the only 'returns' in it belong to the allocating map and to the fiber map φ. The internal _scalar_field_broadcast_data has the same gap.

*Proposed fix.* Close map!'s identity sentence as its siblings do — 'Apply an arbitrary fiber map φ at every base point, writing the result into destination, and return destination.' — and add 'returns the reshaped view' to _scalar_field_broadcast_data.

*Located at:* `docs/src/api/FieldAlgebra.md`.

#### 037 — RULE.DOC.RETURNS

*Status:* open.

*Claim.* Half of the compatibility-check family says what it returns and half does not, so a reader cannot tell whether the silent ones return a value, a Boolean, or nothing.

*Proposed fix.* Give each of the four the sentence its siblings carry, and keep 'Returns true or false' where a Boolean really is returned.

*Located at:* `docs/src/api/Fields.md`, `src/Fields.jl:1256`, `src/Fields.jl:2542`, `src/Fields.jl:908`.

#### 054 — RULE.DOC.RETURNS

*Status:* open.

*Claim.* _check_nufft_compatibility's identity sentence does not say what the call produces, and the docstring carries neither an arrow nor a 'returns' sentence. 'Check that …' leaves a reader unable to tell whether it answers with a Bool he must test or throws on a mismatch — and the answer decides how he calls it.

*Proposed fix.* Close the sentence as its neighbour does: '…, throwing an ArgumentError otherwise.'

*Located at:* `docs/src/api/Interpolation.md`.

#### 058 — RULE.DOC.RETURNS

*Status:* open.

*Claim.* Mutating and checking functions never say what the call returns, while their neighbours on the same page do, so the silence reads as a difference in behaviour.

*Proposed fix.* Add the one sentence each: displace! runs in place and returns the destination point set; each check returns nothing when it passes.

*Located at:* `src/Points.jl:1288`, `src/Points.jl:1350`, `src/Points.jl:480`.

#### 081 — RULE.DOC.RETURNS

*Status:* open.

*Claim.* The prose block standing in for each helper's documentation describes what the helper does but never names what it hands back, and in one case the returned value is genuinely surprising.

*Proposed fix.* Add a result sentence to each block: 'Returns the first-stage tracer velocities, which the driver records for the Lagrangian statistics.'; 'Returns a named tuple of the scratch fields the loop writes into.'; 'Returns the initial velocity field in spectral representation.'

*Located at:* `docs/src/examples/hist_cpu.md`.

#### 017 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The page never says what N is, and then uses it for two different quantities; and the per-axis factors, introduced as g_a, are written sigma_1 sigma_2 sigma_3 in the internal docstring, where sigma is already the page's name for something else.

*Proposed fix.* Bind N once, at its first use, and use one meaning: say 'with N the grid points along one axis' and write the cell volume as $|\Omega|/N^3$, or bind both and distinguish them by symbol. In _apply_separable_convolution!, write the association as $\alpha((g_1 g_2) g_3)\hat f$, matching the symbol SeparableKernel already introduced for the per-axis factors.

*Located at:* `docs/ARCHITECTURE.md:1126`, `docs/DECISIONS.md:215`, `docs/src/api/Convolution.md`, `src/Convolution.jl:805`, `src/Convolution.jl:826`.

#### 028 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The scalars α and β carry the page's accumulate convention and are never bound in plain language; φ is bound to one thing and then used for another.

*Proposed fix.* Say once, where α and β first appear, that α scales the computed result and β the destination accumulated onto; and give the scalar norm its own letter, or name the field the letter stands for.

*Located at:* `docs/src/api/FiberSections.md`, `src/FiberSections.jl:661`.

#### 029 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Two explanations rest on internal names that appear nowhere else on the page, so the reason they offer cannot be followed.

*Proposed fix.* State the reasoning in its own words - a struct rather than a closure keeps the input count in the type - and drop or gloss the bare internal name.

*Located at:* `docs/src/api/FiberSections.md`.

#### 031 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Three symbols carry formulas on this page without ever being bound in plain language: the wavenumber k and the hat that marks a coefficient, in combine!'s kernel-composed form; the position x, in the first formula that uses it; and φ, which norm!'s formula uses for a scalar field while map! uses the same glyph for a fiber map.

*Proposed fix.* Bind k as the wavenumber and the hat as the spectral coefficient where combine!'s kernel form first uses them; bind x as a base point at dot!'s formula rather than at map!'s; and write norm!'s scalar case with the name its signature uses, freeing φ for the fiber map.

*Located at:* `docs/ARCHITECTURE.md:1099`, `docs/DECISIONS.md:778`, `docs/src/api/FieldAlgebra.md`, `src/FieldAlgebra.jl:1408`.

#### 035 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Reasons are given on the page as numbered invariants and decisions, none of which the page states. The number is the whole of the justification offered, and the reader has no way to learn what invariant 5, invariant 14 or decision 76 says.

*Proposed fix.* Replace each citation by the one clause it stands for (the derivative wavenumbers are zeroed at Nyquist so derivatives of real fields stay real; a mixed pair is refused rather than promoted; the components are stored fiber-last and so are contiguous), keeping the numbers for the design documents.

*Located at:* `docs/src/api/Fields.md`, `src/Fields.jl:1433`, `src/Fields.jl:1757`, `src/Fields.jl:908`.

#### 043 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The symbol R carries the whole of the page's tensor-order section — it is the heading's subject, the ceiling, and the parameter the types are said to carry — and it is never bound to a named quantity. The page nowhere says 'tensor order', so R is introduced only by the enumeration R = 0, 1, 2 beside three words, and the reader is left to infer what the letter stands for.

*Proposed fix.* Bind it at first use — 'Scalar, vector and second-order tensor sections — tensor order R = 0, 1, 2 —' — and leave the later uses bare, as they already are.

*Located at:* `docs/DECISIONS.md:2215`, `docs/DECISIONS.md:645`, `docs/FORMALIZATION.md:772`, `docs/FORMALIZATION.md:872`, `docs/src/api/GBGPeriodicFields.md`, `src/GBGPeriodicFields.jl:52`.

#### 051 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Three symbols are used and never bound. The type parameter L is displayed in AbstractSplineScheme's signature and then never mentioned again, while its three siblings N2, M2 and T are all explained in the body; the hat of $\hat f$ and $\hat g$ is the page's notation for the spectral representation and is introduced nowhere; and $\deg$ appears in a parenthetical with no object.

*Proposed fix.* Bind L where its siblings are bound (the SMatrix length); bind the hat once at its first use — 'writing $\hat f$ for the field's spectral representation'; and write $\deg$ as the degree of what.

*Located at:* `docs/ARCHITECTURE.md:1099`, `docs/DECISIONS.md:778`, `docs/src/api/Interpolation.md`, `src/Interpolation.jl:143`, `src/Interpolation.jl:213`, `src/Interpolation.jl:258`.

#### 064 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The symbol $R$ is bound to the covariance tensor and then reused, unbound, for tensor order in the same module docstring.

*Proposed fix.* Keep $R$ for the covariance tensor and write the order restriction in words ("scalar, vector and second-order tensor sections"), or bind the order to its own symbol before using it.

*Located at:* `docs/src/api/Reductions.md`, `src/Reductions.jl:36`.

#### 065 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The per-axis box symbols and a bare box side arrive already in use, and one definite reference has no antecedent.

*Proposed fix.* Bind the per-axis symbols in one clause where they first appear and say which side $L$ is; open the tie-break sentence with "Two neighbouring shells meet at a half-integer …".

*Located at:* `docs/FORMALIZATION.md:622`, `docs/src/api/Reductions.md`, `src/Reductions.jl:1501`.

#### 067 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Four mathematical symbols are used with no binding in plain language at first use, in breach of the promise the page's own second paragraph makes.

*Proposed fix.* Bind each at first use: gloss M and N where they first appear ('M points and N grid nodes'); write the wavenumbers as $2\pi n/L_a$ with n the mode index and $L_a$ the box length on that axis, and choose a different letter for one of the two L's; say '$k_N$, the Nyquist wavenumber'; and say what c is ('c the exponent's coefficient — for a diffusive factor $-\nu\Delta t$').

*Located at:* `docs/ARCHITECTURE.md:1103`, `docs/ARCHITECTURE.md:462`, `docs/ARCHITECTURE.md:475`, `docs/DECISIONS.md:1047`, `docs/src/architecture.md`.

#### 069 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The page carries its reasoning in bare 'decision N' pointers into a document it does not contain, and the citation form itself is explained only in the page's last sentence.

*Proposed fix.* State at the head of the page, where the invariants are announced, that a numbered decision is an entry of docs/DECISIONS.md and link it; and where a decision number is doing the explaining rather than the crediting, put the one-clause reason on this page beside the number.

*Located at:* `docs/ARCHITECTURE.md:1139`, `docs/ARCHITECTURE.md:136`, `docs/ARCHITECTURE.md:695`, `docs/src/architecture.md:1139`, `docs/src/architecture.md:695`, `docs/src/architecture.md`.

#### 071 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* §10 sends the reader to a numbered item the page does not have.

*Proposed fix.* Name the target — a section of this page, or 'decision 17 in docs/DECISIONS.md' — or delete the pointer, the sentence's 'and the references below' already carrying the reader to the van Hinsberg entry.

*Located at:* `docs/ARCHITECTURE.md:939`, `docs/src/architecture.md:939`.

#### 073 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The page's load-bearing constraints are cited only by number — 'invariant 1', 'invariant 5', 'invariant 12', and eight others — and not one of them is stated anywhere on the page.

*Proposed fix.* Gloss each invariant in a clause at its first use in an entry ('invariant 1, that the public method set is the spec'), or open the page with a short numbered list of the invariants the log cites, so a number resolves on the page that uses it.

*Located at:* `docs/DECISIONS.md:329`, `docs/DECISIONS.md:8`, `docs/src/decisions.md:329`, `docs/src/decisions.md:8`, `docs/src/decisions.md`.

#### 074 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Evidence and definitions are deferred to sections and findings of other documents by bare pointer — sixty-six §-numbers, plus lettered findings and named files — none of which the page reproduces or links.

*Proposed fix.* State the borrowed fact in one clause where it is used ('measured at roughly 1.4× on the GPU for a varying exponent') and keep the pointer as a link rather than as the content, so the entry still reads on its own.

*Located at:* `docs/DECISIONS.md:3389`, `docs/src/decisions.md:3389`, `docs/src/decisions.md`.

#### 077 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The symbol N is bound to three incompatible meanings on the page — the number of grid cells, the total grid-point count, and the points per axis — and a reader carrying the first binding silently misreads the later formulas.

*Proposed fix.* Pick one meaning for N, state it once in the page's opening paragraph, and write the other quantity with its own symbol (for example N for the total point count and n for the points per axis), then sweep the cost expressions so each matches its stated binding.

*Located at:* `docs/src/decisions.md`.

#### 080 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Several mathematical symbols are used before they are bound, or are never bound: the dissipation rate is first written as a formula in the driver and only glossed in the closing Results section, and the correlation coefficients, the shell power and the root-mean-square wavenumber are never introduced at all.

*Proposed fix.* Bind at first use: name epsilon the mean dissipation rate where the history is recorded, define rho as the autocorrelation normalized by its value at zero where the integral length is first written, name P of kappa the shell-summed power, and say that kappa-rms is the energy-weighted root-mean-square wavenumber that makes the divergence residual dimensionless.

*Located at:* `docs/src/examples/hist_cpu.md`, `examples/HIST_CPU.jl:172`, `examples/HIST_CPU.jl:344`, `examples/HIST_CPU.jl:403`, `examples/HIST_CPU.jl:412`, `examples/HIST_CPU.jl:507`, `examples/HIST_CPU.jl:523`, `examples/gpu/rocm/HIST_ROCm.jl:129`, `examples/gpu/rocm/HIST_ROCm.jl:194`, `examples/gpu/rocm/HIST_ROCm.jl:364`, `examples/gpu/rocm/HIST_ROCm.jl:424`, `examples/gpu/rocm/HIST_ROCm.jl:432`.

#### 084 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The page's own verification marker — the checkmark printed after a claim, 42 times — is never bound. Nothing on the page says what it asserts (that the expansion was carried out? that a test passes? that the claim is exact rather than scoped?), yet the surrounding prose treats it as the page's verdict.

*Proposed fix.* Bind it once in the opening section — one plain sentence saying that a checkmark marks a statement whose expansion has been carried out against the implementation — before its first use.

*Located at:* `docs/FORMALIZATION.md:110`, `docs/FORMALIZATION.md:255`, `docs/FORMALIZATION.md:314`, `docs/src/formalization.md:255`, `docs/src/formalization.md`.

#### 085 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Several symbols carry load in the statements and are never bound in plain language at first use, though the page opens with a Declarations section that exists to do exactly that. A reader cannot check an expansion whose symbols he must guess.

*Proposed fix.* Bind each at first use, in the Declarations section where it belongs: name $N_{k_x}$ and $|\Omega|$ there; introduce $\kappa$ and $\Delta k$ in a clause when the shell reduction is stated, and give the per-axis use a different glyph; say that $c$ indexes the fiber components and $r$ is the separation; write 'Float64' rather than $\mathbb{F}_{64}$, or bind it; replace the bare $64 \varepsilon$ with 'sixty-four units in the last place'; and name $\mathbb P$ as the Helmholtz projection in the prose before the table.

*Located at:* `docs/ARCHITECTURE.md:1129`, `docs/ARCHITECTURE.md:187`, `docs/ARCHITECTURE.md:293`, `docs/ARCHITECTURE.md:307`, `docs/ARCHITECTURE.md:313`, `docs/ARCHITECTURE.md:316`, `docs/ARCHITECTURE.md:395`, `docs/ARCHITECTURE.md:487`, `docs/ARCHITECTURE.md:496`, `docs/ARCHITECTURE.md:498`, `docs/ARCHITECTURE.md:500`, `docs/ARCHITECTURE.md:505`, `docs/DECISIONS.md:397`, `docs/DECISIONS.md:400`, `docs/DECISIONS.md:419`, `docs/DECISIONS.md:433`, `docs/FORMALIZATION.md:101`, `docs/FORMALIZATION.md:109`, `docs/FORMALIZATION.md:113`, `docs/FORMALIZATION.md:156`, `docs/FORMALIZATION.md:163`, `docs/FORMALIZATION.md:233`, `docs/FORMALIZATION.md:234`, `docs/FORMALIZATION.md:385`, `docs/FORMALIZATION.md:523`, `docs/FORMALIZATION.md:617`, `docs/FORMALIZATION.md:622`, `docs/FORMALIZATION.md:623`, `docs/FORMALIZATION.md:62`, `docs/FORMALIZATION.md:631`, `docs/FORMALIZATION.md:63`, `docs/FORMALIZATION.md:64`, `docs/FORMALIZATION.md:65`, `docs/FORMALIZATION.md:761`, `docs/FORMALIZATION.md:814`, `docs/FORMALIZATION.md:87`, `docs/src/formalization.md:523`, `docs/src/formalization.md:622`, `docs/src/formalization.md`, `src/Reductions.jl:1484`, `src/Reductions.jl:1485`, `src/Reductions.jl:1494`.

#### 101 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The page's symbols are used bare: no sentence binds what the Greek scalars scale, what the f/f! convention is, or what the one worked example's two names denote.

*Proposed fix.* Bind each symbol in the clause that first uses it - say the accumulation scalars weight a computed result and a destination, say that the exclamation mark marks the in-place form, and pick an example whose two names the sentence introduces.

*Located at:* `docs/ARCHITECTURE.md:907`, `docs/DECISIONS.md:2698`, `docs/DECISIONS.md:3431`, `docs/DECISIONS.md:547`, `docs/DECISIONS.md:555`, `docs/FORMALIZATION.md:163`, `docs/FORMALIZATION.md:181`, `docs/FORMALIZATION.md:185`, `docs/FORMALIZATION.md:197`, `docs/FORMALIZATION.md:39`, `docs/FORMALIZATION.md:767`, `docs/FORMALIZATION.md:772`, `docs/src/gbg-rules.md:543`, `docs/src/gbg-rules.md:567`, `docs/src/gbg-rules.md`, `docs/src/notation.md:19`, `examples/HIST_CPU.jl:344`, `examples/HIST_CPU.jl:497`, `examples/HIST_CPU.jl:499`, `examples/HIST_CPU.jl:504`, `examples/HIST_CPU.jl:505`, `examples/HIST_CPU.jl:519`, `examples/HIST_CPU.jl:520`, `examples/HIST_CPU.jl:521`, `examples/HIST_CPU.jl:522`, `examples/HIST_CPU.jl:523`, `examples/gpu/rocm/HIST_ROCm.jl:129`, `examples/gpu/rocm/HIST_ROCm.jl:364`, `src/DifferentialOperators.jl:1087`, `src/DifferentialOperators.jl:1088`, `src/FiberSections.jl:695`, `src/FieldAlgebra.jl:1012`, `src/FieldAlgebra.jl:1016`, `src/FieldAlgebra.jl:1520`, `src/FieldAlgebra.jl:1524`.

#### 107 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The ROCm slowness figure is a comparison whose second term is never given: Float32 is said to be 'within about 10%' of nothing the sentence names.

*Proposed fix.* Name the baseline in the clause: 'where the Float32 forms are within about 10% of the same NVIDIA card'.

*Located at:* `docs/src/gpu.md`.

#### 111 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The Interpolation entry introduces two symbols, N and M, in the one statement a reader would want to take away from it, and binds neither; the page never says anywhere that N counts the grid's points and M the unstructured ones.

*Proposed fix.* Bind both letters in the clause: '... exactly L2-adjoint once rescaled by the ratio of the grid's point count N to the point set's count M'. The vocabulary paragraph already establishes the grid and the point set, so the binding costs one clause.

*Located at:* `docs/src/index.md`.

#### 116 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Two symbols appear on the notation page and are never bound: the measure in the differential and the integral, and the per-axis grid size inside the product that defines the grid-point count.

*Proposed fix.* Bind both where they first appear: name the measure in the differential row (the base measure — cell volume on a grid, counting on a point set), and write the N row as 'the grid-point count, the product of the per-axis counts N_i'.

*Located at:* `docs/ARCHITECTURE.md:1114`, `docs/ARCHITECTURE.md:159`, `docs/ARCHITECTURE.md:393`, `docs/ARCHITECTURE.md:834`, `docs/DECISIONS.md:182`, `docs/DECISIONS.md:189`, `docs/DECISIONS.md:196`, `docs/DECISIONS.md:258`, `docs/FORMALIZATION.md:523`, `docs/FORMALIZATION.md:524`, `docs/FORMALIZATION.md:534`, `docs/FORMALIZATION.md:587`, `docs/FORMALIZATION.md:670`, `docs/src/notation.md:16`, `docs/src/notation.md:31`, `docs/src/notation.md:60`, `docs/src/notation.md`, `examples/HIST_CPU.jl:412`, `examples/HIST_CPU.jl:417`, `examples/HIST_CPU.jl:507`, `examples/HIST_CPU.jl:509`, `examples/gpu/rocm/HIST_ROCm.jl:432`, `examples/gpu/rocm/HIST_ROCm.jl:435`, `src/Convolution.jl:981`, `src/DifferentialOperators.jl:1400`, `src/DifferentialOperators.jl:1401`, `src/DifferentialOperators.jl:1407`, `src/DifferentialOperators.jl:1408`, `src/Reductions.jl:469`, `src/Reductions.jl:476`, `src/Reductions.jl:488`, `src/Reductions.jl:497`, `src/Reductions.jl:765`.

#### 117 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The page gives one glyph two incompatible readings and then hands the reader the job of deciding which is meant, with the deciding authority placed in a docstring the reader of this page does not have.

*Proposed fix.* Use two symbols, or state the per-axis reading explicitly where it is used: write the storage claims over the per-axis count N_i (a full field is O(N_i^3) = O(N)), so no expression needs a reading chosen by the reader.

*Located at:* `docs/DECISIONS.md:453`, `docs/src/notation.md:31`, `docs/src/notation.md`.

#### 120 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Math symbols are used with no binding in plain language, so a cold reader cannot tell what quantity a ratio is indexed by.

*Proposed fix.* Bind each on first use, in the sentence that first needs it: the tensor order R, the stencil width W, the wavenumber magnitude (and use one glyph for it, k or kappa, not both), the per-mode field w-hat, the radial symbol sigma.

*Located at:* `docs/PERFORMANCE.md:244`, `docs/PERFORMANCE.md:252`, `docs/PERFORMANCE.md:645`, `docs/PERFORMANCE.md:955`, `docs/src/performance.md:244`, `docs/src/performance.md:252`, `docs/src/performance.md:955`.

#### 124 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Numbered invariants and a numbered policy section of another document are cited as the whole of an argument, so the step they carry cannot be followed here.

*Proposed fix.* State the content of the invariant in the clause that invokes it and keep the number as a pointer, as the invariant 6 mention already does.

*Located at:* `docs/PERFORMANCE.md:1093`, `docs/PERFORMANCE.md:1433`, `docs/src/performance.md:1093`, `docs/src/performance.md:1433`.

#### 131 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* The measure and spectral notation the page reasons with is never bound: the grid count N, the point count M, the domain measure |Ω|, the wavenumber k and the hat for the spectral representation all appear in formulas with no plain-language gloss anywhere on the page.

*Proposed fix.* Bind each at first use: N the number of grid points and M the number of points in the set; |Ω| the volume of the periodic box; k the wavenumber vector; and one clause saying that a hat denotes a field's spectral representation, at the first formula that wears one.

*Located at:* `docs/ARCHITECTURE.md:1086`, `docs/ARCHITECTURE.md:196`, `docs/ARCHITECTURE.md:314`, `docs/ARCHITECTURE.md:316`, `docs/ARCHITECTURE.md:818`, `docs/ARCHITECTURE.md:873`, `docs/ARCHITECTURE.md:894`, `docs/DECISIONS.md:182`, `docs/DECISIONS.md:183`, `docs/DECISIONS.md:185`, `docs/DECISIONS.md:186`, `docs/DECISIONS.md:195`, `docs/DECISIONS.md:274`, `docs/DECISIONS.md:317`, `docs/DECISIONS.md:519`, `docs/DECISIONS.md:731`, `docs/FORMALIZATION.md:606`, `docs/FORMALIZATION.md:661`, `docs/TESTING.md:653`, `docs/TESTING.md:659`, `docs/TESTING.md:686`, `docs/src/testing.md`, `src/Reductions.jl:984`.

#### 132 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Several symbols are used long before — or entirely without — the clause that binds them, and one glyph is given two meanings on the same page.

*Proposed fix.* Bind the tensor order R at its first use in §2 rather than in §4; name E and R in that formula ('E the embedding, R the extraction') or, since R is taken, rename one of them; and gloss c as the component index, a as the axis index and N_a as the point count along axis a.

*Located at:* `docs/TESTING.md:175`, `docs/TESTING.md:427`, `docs/src/testing.md`.

#### 141 — RULE.DOC.SELF_CONTAINED

*Status:* open.

*Claim.* Three symbols carry load on the page and none is bound in plain language: the hat for the spectral representation, k for a wavenumber, and the pair P and κ in the spectrum's own comment.

*Proposed fix.* Bind the hat and k in the sentence that first uses them ("writing $\hat f$ for the field's spectral representation and $k$ for a wavenumber vector"), and either bind P(κ) as the spectrum at shell wavenumber κ or write the comment in the words the prose already uses.

*Located at:* `docs/DECISIONS.md:2568`, `docs/DECISIONS.md:776`, `docs/FORMALIZATION.md:103`, `docs/FORMALIZATION.md:119`, `docs/FORMALIZATION.md:69`, `docs/src/tutorial.md:126`, `docs/src/tutorial.md:41`, `docs/src/tutorial.md`.

#### 005 — RULE.DOC.STEER

*Status:* open.

*Claim.* Four in-place forms that have an allocating sibling do not carry the steer sentence as the template gives it: to_physical! and to_spectral! carry no steer at all, translation_kernel! rewrites it, and point_traversal_order! ends 'a fresh order instead' where the template says 'a fresh result instead'. Separately, the five steers whose sibling is an operator write that sibling in plain backticks, where the rule requires it as an @ref link so the link resolves. CLAUDE.md records the to_physical!/to_spectral! omission and the translation_kernel! rewording as deliberate exemptions, but .gbg/config.jl declares no Switch on this rule, and the rulebook says an exception is a Switch.

*Proposed fix.* Give to_physical! and to_spectral! the verbatim sentence naming their own destination arguments (`physical` and `spectral`) and @ref-linking to_physical / to_spectral, keeping the existing input-preservation warning where it is. Reword translation_kernel!'s to 'Use this in-place form when `kernel` is already allocated; the allocating [`translation_kernel`](@ref) returns a fresh result instead.' and point_traversal_order!'s ending to 'a fresh result instead'. Promote the operator siblings to @ref links. If any of these is genuinely meant to stand, declare a Switch on RULE.DOC.STEER in .gbg/config.jl naming the files and the reason, so the exemption lives where a reader of the rulebook will find it.

*Located at:* `src/Convolution.jl:1958`, `src/FieldAlgebra.jl:1114`, `src/FieldAlgebra.jl:233`, `src/FieldAlgebra.jl:255`, `src/FieldAlgebra.jl:603`, `src/FieldAlgebra.jl:626`, `src/Fields.jl:1523`, `src/Fields.jl:1582`, `src/Interpolation.jl:883`.

#### 018 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Four nouns the page leans on are the package's own and are never defined or linked on it: the fiber of a field, the base a cost depends on, a section, and the trailing kernel argument of a fused operator.

*Proposed fix.* Bind each at first use on the page, or @ref-link it: 'the fiber — the value a field carries at one base point, a scalar, a vector or a 3x3 tensor'; 'the base — the grid the field lives on'; 'a section — a field or point-value array over that base'; and, for the fused operators, name them (divergence!, helmholtz_projection!) and link the page that documents the trailing-kernel arity, as the exponential_convolve! docstring already does.

*Located at:* `docs/src/api/Convolution.md`, `src/Convolution.jl:6`.

#### 024 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* A second class of package nouns is used with the module's context assumed. The multipliers bullet of inverse_curl! makes three properties — layout, element type and storage family — binding on a call without saying what a layout or a storage family is, and it is the only bullet on the page that states the requirement at all. The module map points at 'the explicit six-array constructor' without saying what the six arrays are, so the alternative it offers cannot be taken. The Internal API section defines 'gated' in a clause, which is exactly right, and then uses 'slab-threaded', '_tensor2_component_data' and 'the lazy _squared_wavenumber_broadcast' on the same terms as 'gated' but with no clause.

*Proposed fix.* Give each the one clause the page gives 'gated': say what a layout and a storage family are where the refusal is stated, name what the six arrays hold, and gloss 'slab-threaded' (a loop split into contiguous slabs of the grid) at its first use. The two internal names are the ordering convention and the lazy squared-wavenumber broadcast; say so where they are cited.

*Located at:* `docs/src/api/DifferentialOperators.md`, `src/DifferentialOperators.jl:1178`.

#### 032 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The module docstring defines base, fiber and section, and then four package terms of art are used as though they had been defined too: 'storage-wise', 'the executor's parallelism' with its 'slab-threaded loop', and a kernel's 'storage classes' / 'compressed class', the last three deferring to a convolve! that is not on this page.

*Proposed fix.* Say what storage-wise means in the clause that uses it or drop the word; replace 'the executor's parallelism' with the plain statement already in its parenthesis (a device kernel on a GPU, a threaded loop on a CPU); and name the kernel storage classes, or @ref-link convolve!, so combine!'s kernel bullet stands without the other page.

*Located at:* `docs/src/api/FieldAlgebra.md`, `src/FieldAlgebra.jl:1809`, `src/FieldAlgebra.jl:241`, `src/FieldAlgebra.jl:553`.

#### 034 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page uses the package's own structural vocabulary — section, fiber, base — without ever defining it, and in one case defines it far below its first use. A reader who has not read the design documents cannot tell what a 'section' is, what a 'fiber' is, or that 'the base' means the grid.

*Proposed fix.* Bind each term in a clause at its first use on the page: say that a field is a section (a value attached to every point of the grid), that the fiber is the value at one point (a scalar, a 3-vector, a 3x3 array), and that the base is the grid the section lives over — or link each to the notation page.

*Located at:* `docs/src/api/Fields.md`, `src/Fields.jl:1233`, `src/Fields.jl:1305`, `src/Fields.jl:1716`, `src/Fields.jl:246`, `src/Fields.jl:247`, `src/Fields.jl:266`, `src/Fields.jl:267`.

#### 039 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Prose on the page appeals to files and test lanes of the repository, which a reader of the documentation cannot open and has not been told exist.

*Proposed fix.* State the property instead of the instrument — the two wrappers cost a constant 128 bytes a call, and both arms compute each element once and agree bitwise — and leave the test names to the repository.

*Located at:* `docs/src/api/Fields.md`, `src/Fields.jl:2736`, `src/Fields.jl:2738`.

#### 041 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Objects the page hands the reader as already-known: multipliers, kernels, transform plans and the two wavenumber families are named as things the package has, but the page never says what any of them is. They sit inside the block that opens 'These words recur in every operation's documentation', which is where the page promises its vocabulary, so a reader who stops to look them up finds the promise unkept.

*Proposed fix.* Give each a defining clause at first use, in the same shape the block already uses for base, fiber and section: a kernel is a transfer function a field is convolved against; multipliers are the per-mode wavenumber arrays the differential operators multiply by, in two families — the derivative wavenumbers, zeroed at an even axis's Nyquist frequency, and the squared wavenumbers, which keep the true value there; transform plans are the precomputed FFT plans a grid's transforms run through. The wavenumber-family clause can then carry the resolved-band sentence, which currently has to lean on it.

*Located at:* `docs/src/api/GBGPeriodicFields.md`, `src/GBGPeriodicFields.jl:29`, `src/GBGPeriodicFields.jl:84`.

#### 042 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The tensor-order section names groups of operations by house shorthand — the fiber-preserving and mapped reductions, the decomposition family, the bare maximum, the vector-space operations, the local-spline transfer — none of which is defined or linked on this page. The section's whole point is to tell a reader which operations stop at second order, and it answers in vocabulary he does not have.

*Proposed fix.* Name the members or bind the group in a clause: 'the decomposition family (sym, skew, dev)'; 'a mapped reduction, which takes a fiber map as its leading argument, and the bare form, which does not'. Where the group is large, link it to the module page that owns it rather than naming it bare.

*Located at:* `docs/src/api/GBGPeriodicFields.md`.

#### 045 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Three pieces of the project's own working vocabulary are used as if they were ordinary English: 'the umbrella' as a noun for the top-level module, 'surface' for a set of public methods, and 'a test lane' for a part of the test suite. The first has no antecedent on the page at all, and the last speaks about the repository rather than about the package a reader is being taught to use.

*Proposed fix.* Say 'The top-level module' (the page's own later wording) and 'its public interface' (likewise). For the last sentence, state the guarantee without naming the instrument: 'Above the ceiling an operation either works or raises; none returns a wrong answer.'

*Located at:* `src/GBGPeriodicFields.jl:52`, `src/GBGPeriodicFields.jl:64`, `src/GBGPeriodicFields.jl:72`.

#### 046 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page's four load-bearing nouns — section, fiber, base, storage family — are used from the first sentence onward and never defined or linked to a definition anywhere on it. A scientist who knows turbulence and interpolation but not this package cannot tell what a 'section' is, what a 'fiber contraction' contracts, or what makes two arrays the same 'storage family'; these are the package's own vocabulary, not the field's.

*Proposed fix.* Bind each at first use in a clause, or @ref-link it to its definition: 'section' in the module identity sentence, 'fiber'/'base' where inner is glossed, and 'storage family' once (a clause such as 'the array type the data lives in — Array, CuArray or ROCArray') at its first appearance.

*Located at:* `docs/src/api/Interpolation.md`, `src/Interpolation.jl:1127`, `src/Interpolation.jl:1239`, `src/Interpolation.jl:1659`, `src/Interpolation.jl:17`.

#### 047 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Two internal docstrings name a package rule by number alone — 'invariant 14' and 'decision 40' — and the page states neither. The number is the whole of the reference, so the sentence carrying it cannot be understood at all from this page: the reader is told a constraint exists and is given only its index.

*Proposed fix.* Say the thing rather than its number: 'which the package refuses to mix' and 'a threaded float reduction would need a fixed summation tree'. Keep the number, if it is wanted, only as a parenthetical after the statement.

*Located at:* `docs/DECISIONS.md:3325`, `docs/src/api/Interpolation.md`, `src/Interpolation.jl:2083`, `src/Interpolation.jl:684`.

#### 048 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* interpolate!'s 'out' argument is sold on serving 'tensor orders above the usual ceiling', but the page never says what the usual ceiling is. The sentence is an advantage the reader cannot size: it names a limit, places the operation above it, and leaves the limit blank.

*Proposed fix.* Name the ceiling in the clause — 'above the second-order ceiling most of the package stops at' — so the comparison has both of its terms.

*Located at:* `src/Interpolation.jl:1113`.

#### 055 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page cites package artifacts by number or repository path — invariants, a decision, a test file — that it never defines, so a first reader is told the reason lives somewhere they cannot see.

*Proposed fix.* State the substance in the clause ("the accumulation scalars the package writes α and β", "the package refuses a mixed pair rather than converting it") and drop the number, or link the numbered entry.

*Located at:* `docs/src/api/Points.md:73`, `docs/src/api/Points.md`, `src/Points.jl:1233`, `src/Points.jl:1346`.

#### 056 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Package terms of art are used before any clause defines them: the fiber-last layout, a values function, the section interface, a transfer operator and its stencil.

*Proposed fix.* Bind each noun in the clause that first uses it — "fiber-last (the fiber axes trail the base axes)", "a transfer operator, which samples a field at the points" — or @ref-link it to where it is defined.

*Located at:* `src/Points.jl:116`, `src/Points.jl:1327`, `src/Points.jl:13`, `src/Points.jl:22`.

#### 060 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page's core vocabulary — section, base, fiber, fiberwise algebra, tensor order — is used from the first sentence onward and never defined or linked on this page.

*Proposed fix.* Bind each in a clause at first use in the module docstring — a section is a field or a set of point-values, its base is the grid or point set it lives over, its fiber is the value at one base point, tensor order is the rank of that value — or @ref-link them to the page that defines them.

*Located at:* `docs/ARCHITECTURE.md:320`, `docs/src/api/Reductions.md`.

#### 061 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The kernel "storage classes" are counted and reasoned about on this page but never named or listed on it, so the reader cannot tell which four are meant or which one is exempt.

*Proposed fix.* Name the four classes at first mention, or @ref-link SpectralKernel once and let its catalogue carry them.

*Located at:* `docs/src/api/Reductions.md`, `src/Reductions.jl:980`.

#### 062 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The rfft half-spectrum weight and the "folded axis" it lives on are invoked in `inner` as if already known, and first explained two docstrings later.

*Proposed fix.* Give `inner` a one-clause gloss of the weighting (a real field stores half its coefficients, so each non-self-conjugate mode counts twice) and bind "folded axis" once in plain words before fft_dims[1] is named.

*Located at:* `docs/src/api/Reductions.md`, `src/Reductions.jl:752`.

#### 063 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Two references point at project history and at Documenter's machinery, neither of which a reader of this page can resolve.

*Proposed fix.* State the fact without the date ("both now reduce on the same tree, so they agree as threads are added") and drop or reword the assembly remark so it does not depend on knowing how the page is generated.

*Located at:* `docs/src/api/Reductions.md`, `src/Reductions.jl:1022`.

#### 068 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* §9's obligations and §10's scheme catalogue turn on package nouns that the page never defines — a pass-audit row, a fused ideal, a named holder, a dispatch-target guard, the safe polarity, the divergence-free reference.

*Proposed fix.* Gloss each in a clause at first use — 'the pass-audit row (the frozen count of element reads and writes the operation makes)', 'its fused ideal (the traffic a single fused pass would need)', 'a named holder (a recorded, justified gap above that ideal)', 'the dispatch-target guard (a test asserting the CPU twin is the method actually called)' — or drop the term for the thing it names.

*Located at:* `docs/ARCHITECTURE.md:731`, `docs/ARCHITECTURE.md:758`, `docs/ARCHITECTURE.md:902`, `docs/src/architecture.md:758`, `docs/src/architecture.md`.

#### 070 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Measurements are named by a bare parenthesised letter in a file the reader does not have, and one such label is used as the name of a design candidate.

*Proposed fix.* Say what each finding found in the clause that cites it — 'ran at a fixed element rate independent of precision (PERFORMANCE.md finding (o))' already does this and is the model — and replace 'the finding-(k) hoist' with what is to be hoisted, for example 'hoisting the per-mode symbol out of the fiber loop so it is evaluated once per mode rather than once per component'.

*Located at:* `docs/ARCHITECTURE.md:719`, `docs/src/architecture.md`.

#### 075 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* In-house abbreviations and workshop jargon are used as though the reader shared the project's context: 'PF', 'M2 + M3', 'the gate', 'a hat', a 'named holder', 'the canary lane'.

*Proposed fix.* Expand each on first use — 'this package (GBGPeriodicFields)', 'the M2 and M3 method families (the vector-space operations and the tensor contractions)', 'one reviewer', 'the default test suite (the gate)' — or drop the shorthand where the plain noun is no longer.

*Located at:* `docs/DECISIONS.md:1066`, `docs/DECISIONS.md:2402`, `docs/DECISIONS.md:24`, `docs/src/decisions.md:1066`, `docs/src/decisions.md:2402`, `docs/src/decisions.md`.

#### 076 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The vocabulary the whole log is written in — section, base, fiber, the folded axis — is used from the early entries onward and defined, if at all, only far later on the page.

*Proposed fix.* Bind the four terms in the page's opening paragraph, where the promise that each entry stands alone is made, and keep the later restatements as reminders rather than as the first definition.

*Located at:* `docs/DECISIONS.md:160`, `docs/DECISIONS.md:319`, `docs/src/decisions.md:160`, `docs/src/decisions.md:319`, `docs/src/decisions.md`.

#### 079 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Terms of art belonging to the package — fiber, tensor order and 'rank-R field', gather, the shell-resolved inner, half-spectrum weighting — are used on this page with no defining clause and no link to one.

*Proposed fix.* Bind each on first use in a clause: the fiber as the three (or nine) components carried at one grid point, the tensor order as the number of those indices, gather as reading grid values at off-grid points, the shell-resolved inner as the inner product accumulated per wavenumber shell. Alternatively @ref-link each to the page that defines it.

*Located at:* `docs/src/examples/hist_cpu.md`.

#### 086 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The numbered invariants and decisions are used as the page's premises — a step of an argument turns on one — but not one of them is stated on the page. A reader meeting 'which invariant 5 guarantees' is told the conclusion follows and given no way to see that it does.

*Proposed fix.* State the invariant in the clause that uses it — 'which the Nyquist split guarantees: one derivative-wavenumber family serves every first-order operator (invariant 5)' — so the numbered citation becomes provenance rather than the content of the step; the same for invariants 1 and 4, which each take one clause.

*Located at:* `docs/FORMALIZATION.md:290`, `docs/src/formalization.md`.

#### 087 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Package nouns are used before, or without, a defining clause. Each reads as ordinary English to someone who already holds the package's context and as nothing at all to a reader who does not.

*Proposed fix.* Move the gloss to the first use — 'the folded axis (the one axis the real transform stores by half, fft_dims[1] by default)' — and give each of the others a clause: 'a downstream package'; 'the per-array element reads and writes, measured against the fused ideal'; and either define SpectralKernel where it first appears or move the storage-class paragraph ahead of it.

*Located at:* `docs/FORMALIZATION.md:627`, `docs/FORMALIZATION.md:628`, `docs/FORMALIZATION.md:67`, `docs/FORMALIZATION.md:820`, `docs/TESTING.md:666`, `docs/src/formalization.md`, `examples/HIST_CPU.jl:172`, `examples/gpu/rocm/HIST_ROCm.jl:194`.

#### 105 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page names the package's own objects — multipliers, kernels, point sets, a co-spectrum, field_data — without ever saying what any of them is, and 'kernel' collides on this very page with the GPU kernel a reader will assume it means.

*Proposed fix.* Bind each in a clause at first use, the way 'storage family' already is: say that multipliers are the per-mode factors the differential operators apply, that a kernel is a transfer function applied in the spectral representation (and, where GPU kernels are meant, write 'GPU kernels'), that a point set is the unstructured base of sampling positions, and that field_data returns the array holding a field's values. Name the co-spectrum's two-field form or drop it.

*Located at:* `docs/src/gpu.md:152`, `docs/src/gpu.md`.

#### 106 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Both vendor sections make a load-bearing demand about 'the layout' and 'axes reordered' that the page never defines, and no signature it shows takes a layout at all, so the reader cannot tell whether he is obeying it.

*Proposed fix.* Add a clause where the term first appears — a layout records which array axis carries which spatial direction and which axis the real-to-complex transform folds, the default being RealFourierLayout — and show the constructor arity that takes one, or state plainly that the constructors on this page cannot produce a non-default layout so the caveat concerns readers who built one elsewhere.

*Located at:* `docs/src/gpu.md:145`, `docs/src/gpu.md`.

#### 109 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page defines base, fiber, section and the transfer verbs, and then spends its two catalogue lists on package nouns it never defines and that a first reader meets here for the first time — a kernel and its storage classes, a field's multipliers and plans, fused, spectral-only. In two of these the definition does exist on the page but arrives later than the use.

*Proposed fix.* Bind each of these in the clause where it first appears, the way the vocabulary paragraph binds section and fiber: say that a kernel is a transfer function multiplying the coefficients (and that the storage classes are ways of holding it, from one coefficient per mode to a closed-form symbol), that the multipliers are the per-mode wavenumber factors the operators apply and a plan is a precomputed transform, that fused means computed in a single pass, and that spectral-only means the operation is defined on a field in its spectral representation alone. Alternatively move the Convolution entry's kernel sentence up to the vocabulary paragraph, where the terms it needs are already being introduced.

*Located at:* `docs/src/index.md:47`, `docs/src/index.md:48`, `docs/src/index.md`.

#### 114 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The word 'fiber' is never defined on the page, although a whole section is headed 'Base and fiber' and the term is used, in three different adjectival forms, before and after that heading; the base gets its own row and its own sentence, the fiber gets neither.

*Proposed fix.* Give the fiber a row of its own beside B, or bind it in the f row: 'the value at one point is the fiber — a scalar, a vector or a second-order tensor — and a fiber index numbers its components'.

*Located at:* `docs/src/notation.md:15`, `docs/src/notation.md:55`, `docs/src/notation.md:58`, `docs/src/notation.md:69`, `docs/src/notation.md`, `src/Fields.jl:581`, `src/Fields.jl:659`.

#### 115 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* Package terms are used before the page defines them, or are glossed only by pointing at a document the reader does not have: 'section' is handed to the design docs, 'the base' is used a row before B introduces it, 'anterpolation' is used in the q row and named only much later in the W-transpose row, and 'the base measure' is never explained at all.

*Proposed fix.* Bind each at first use on this page: a section is a value attached to every point of the base; anterpolation is the scatter of point values onto the grid (say it in the q row, or link the W-transpose row); the base measure is the grid cell volume on a Grid3D and the counting measure on a PointSet.

*Located at:* `docs/src/notation.md:28`, `docs/src/notation.md:60`, `docs/src/notation.md`.

#### 121 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The package's own structural vocabulary — fiber, base point, section, the fixed tree, the pass audit — carries the explanations and is never defined on the page.

*Proposed fix.* Give each a defining clause at first use — a fiber is the value carried at one grid point and a section is a field seen as that value at every point; the fixed tree is the threaded reduction; the pass audit is the per-element read/write ledger — or link the glossary that defines them.

*Located at:* `docs/DECISIONS.md:2905`, `docs/PERFORMANCE.md:131`, `docs/PERFORMANCE.md:410`, `docs/PERFORMANCE.md:449`, `docs/PERFORMANCE.md:83`, `docs/src/performance.md:131`, `docs/src/performance.md:449`, `docs/src/performance.md:83`, `src/Reductions.jl:420`.

#### 122 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The initialism IT names something the page never identifies, and it is cited as the source of measurements and of a numbered work item.

*Proposed fix.* Expand it on first use — name the consuming package and link it — and give the item its subject rather than its number.

*Located at:* `docs/PERFORMANCE.md:1519`, `docs/PERFORMANCE.md:2221`, `docs/PERFORMANCE.md:474`, `docs/src/performance.md:1519`, `docs/src/performance.md:2221`, `docs/src/performance.md:474`.

#### 123 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The lettered findings do not run in order, so several terms are used pages before the paragraph that introduces them.

*Proposed fix.* Order the lettered findings so a term is introduced before it is used, or, where an entry must stay where it is, give the term its defining clause at the earlier mention.

*Located at:* `docs/PERFORMANCE.md:2254`, `docs/src/performance.md:2254`.

#### 133 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The package's bundle vocabulary — section, fiber, base — is used as load-bearing terminology and never defined on the page.

*Proposed fix.* Define the three in one clause at first use — a section being a field or a point-value container, the base being the grid or point set it is defined over, and the fiber being the value it carries at one base point — or @ref-link them to the page that defines them.

*Located at:* `docs/TESTING.md:340`, `docs/TESTING.md:678`, `docs/src/testing.md:340`, `docs/src/testing.md:678`.

#### 134 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page's own coinages for suite machinery are used as if already known: the M2/M3 surfaces, the carrier gate and carrier kinds, a single-carrier operation, a named holder, and the fold.

*Proposed fix.* Give each a defining clause at first use — what M2 and M3 group, what a carrier is and what the gate over carriers checks, what a holder holds, and that the fold is the axis permutation the real transform is taken along — or link each to where it is defined.

*Located at:* `docs/DECISIONS.md:1655`, `docs/DECISIONS.md:3433`, `docs/FORMALIZATION.md:165`, `docs/TESTING.md:139`, `docs/TESTING.md:151`, `docs/TESTING.md:324`, `docs/TESTING.md:506`, `docs/src/testing.md:139`, `docs/src/testing.md:151`, `docs/src/testing.md:324`, `docs/src/testing.md:506`, `docs/src/testing.md`.

#### 135 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The page states requirements by citing numbered invariants and numbered decisions whose content it never gives, so the sentences carrying them say nothing to a reader of this page alone.

*Proposed fix.* State the substance beside the number at first use — 'invariant 1, that the public method set is the spec' — and say once, early, that a numbered decision is an entry in the package's decision log, with a link to it; after that the bare number is readable.

*Located at:* `docs/DECISIONS.md:54`, `docs/TESTING.md:508`, `docs/TESTING.md:541`, `docs/src/testing.md:508`, `docs/src/testing.md:541`, `docs/src/testing.md`.

#### 138 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The bundle vocabulary the page reasons in — section, tensor bundle, base, and the base's measure — is used throughout and defined nowhere on the page. Only fiber is given a clause.

*Proposed fix.* Bind the two nouns where fiber is already bound, in the same sentence: the base is the set of points the field is defined over (the grid, or a PointSet), the fiber is the value space over each of them, and the base's measure is the cell volume on a grid and the count on a point set.

*Located at:* `docs/src/index.md:51`, `docs/src/tutorial.md:167`, `docs/src/tutorial.md:91`, `docs/src/tutorial.md:92`, `docs/src/tutorial.md:9`, `docs/src/tutorial.md`.

#### 139 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* The convolution section introduces the kernel vocabulary — storage class, symbol, mode — as if the reader already held it, in the one sentence that has to carry the whole idea that a kernel is not a field.

*Proposed fix.* Say it in a clause: a kernel's symbol is the factor it multiplies each Fourier coefficient by, and the package stores that symbol in whichever form it admits — as one number per mode, as per-axis factors, or as the formula itself, evaluated where it is needed.

*Located at:* `docs/src/tutorial.md:133`, `docs/src/tutorial.md`.

#### 140 — RULE.DOC.TERMS_DEFINED

*Status:* open.

*Claim.* One concept is given two names on the page and the two are never joined: the field's tensor order is introduced first, then the plans paragraph switches to rank, and to backend, without a clause binding either.

*Proposed fix.* Use tensor order throughout, or bind rank to it once at first use; and either name the backends the page means (CPU arrays, CUDA, ROCm) or drop the word here.

*Located at:* `docs/src/tutorial.md:65`, `docs/src/tutorial.md`.

#### 008 — RULE.DOC.TWO_TIER

*Status:* open.

*Claim.* Module docstrings carry formulas, where the rule says a map carries a linked one-liner per operation family and no formula. Interpolation is the clearest: it carries a whole ```math block deriving the gather/scatter adjointness identity, plus the componentwise definitions of W and W-transpose, before its contents list. Reductions states the covariance tensor's entries and FieldAlgebra the weighted combination in its family bullet. Each of these formulas already has a home in the operation's own docstring, which is the second place the same mathematics is now maintained.

*Proposed fix.* Cut the display block and the componentwise W / W-transpose definitions from Interpolation's module docstring, keeping the one-sentence statement that the two are exact transposes and linking interpolate! / anterpolate! and the formalization page for the identity. In Reductions replace 'cov (R) with entries R_ij = <u'_i u'_j>' with a bare one-liner naming cov as the vector second central moment and linking it; in FieldAlgebra replace 'combine! (alpha a + beta b)' with 'combine!, the real-weighted combination of two fields'.

*Located at:* `src/FieldAlgebra.jl:24`, `src/Interpolation.jl:10`, `src/Interpolation.jl:22`, `src/Reductions.jl:36`.

#### 009 — RULE.DOC.VERIFIED

*Status:* open.

*Claim.* `cov`'s leading identity states the population covariance while the function returns the Bessel-corrected one by default. The docstring opens with R_ij = <u'_i u'_j>, and <.> is bound on the notation page as the base average — a division by the count — but _covariance multiplies that by count/(count-1) whenever `corrected` is true, which is the default. The same population statement is repeated in the Reductions module docstring. docs/FORMALIZATION.md states the corrected form correctly, so the prose and the formalization of one operation disagree.

*Proposed fix.* Write cov's identity at the default the function has, the way var's already is: 'the sample covariance tensor R_ij = (1/(N-1)) sum_n u'_i(n) u'_j(n) over a grid's N cells and (1/(M-1)) sum_p over a point set's M points', and say in the `corrected` bullet that `false` gives the population form <u'_i u'_j>. Make the same correction in the Reductions module bullet (which the TWO_TIER finding proposes reducing to a one-liner anyway) and in the decision-log entry if it is being touched.

*Located at:* `docs/FORMALIZATION.md:565`, `src/Reductions.jl:36`, `src/Reductions.jl:666`.

#### 038 — RULE.TEX.CODE_SPAN_JULIA

*Status:* open.

*Claim.* Mathematics is written as bare text in a few places where the rest of the page renders it, so an inequality and a wavenumber spacing appear as running words instead of formulas.

*Proposed fix.* Set both as mathematics — a field of order $R > 0$, and a grid of $N$ points over a domain of length $L$ resolving integer multiples of $2\pi/L$ — leaving backticks for names that appear in the code.

*Located at:* `docs/src/api/Fields.md`.

#### 127 — RULE.TEX.CODE_SPAN_JULIA

*Status:* open.

*Claim.* The one backtick span that survives onto the page does not hold well-formed Julia, and it renders with its backticks showing.

*Proposed fix.* Name the two macros separately as real Julia identifiers, each in its own span, and check why this span's backticks survived into the rendered text when every other code name on the page is set properly.

*Located at:* `docs/src/performance.md`.

#### 014 — RULE.TEX.NO_HSCROLL

*Status:* partly fixed. `examples/HIST_CPU.jl`'s code lines are wrapped to 92 columns in 2f225a9c, except the two `@printf` format strings; the three `docs/src/tutorial.md` doctest lines are still open.

*Claim.* Rendered code blocks run past the page and scroll sideways: 67 lines exceed the article's code width (about 92 characters at 14px in a 52rem article), 53 of them beyond any doubt, the worst at 119 characters. Almost all are a statement plus a trailing comment; the reader must drag the block to read the comment that explains the line.

*Proposed fix.* Bring every rendered code line back under about 88 characters: lift the trailing comment onto its own line above the statement, shorten it, or break the call with a hanging indent under the first argument — the same wrapping the signatures already use. For the doctest lines in tutorial.md, bind the long constructor argument to a name on a previous line.

*Located at:* `docs/src/tutorial.md:126`, `docs/src/tutorial.md:51`, `docs/src/tutorial.md:76`, `examples/HIST_CPU.jl:105`, `examples/HIST_CPU.jl:116`, `examples/HIST_CPU.jl:140`, `examples/HIST_CPU.jl:141`, `examples/HIST_CPU.jl:142`, `examples/HIST_CPU.jl:148`, `examples/HIST_CPU.jl:163`, `examples/HIST_CPU.jl:164`, `examples/HIST_CPU.jl:176`, `examples/HIST_CPU.jl:177`, `examples/HIST_CPU.jl:191`, `examples/HIST_CPU.jl:192`, `examples/HIST_CPU.jl:195`, `examples/HIST_CPU.jl:224`, `examples/HIST_CPU.jl:248`, `examples/HIST_CPU.jl:250`, `examples/HIST_CPU.jl:253`, `examples/HIST_CPU.jl:255`, `examples/HIST_CPU.jl:286`, `examples/HIST_CPU.jl:287`, `examples/HIST_CPU.jl:288`, `examples/HIST_CPU.jl:311`, `examples/HIST_CPU.jl:319`, `examples/HIST_CPU.jl:330`, `examples/HIST_CPU.jl:335`, `examples/HIST_CPU.jl:347`, `examples/HIST_CPU.jl:349`, `examples/HIST_CPU.jl:351`, `examples/HIST_CPU.jl:366`, `examples/HIST_CPU.jl:369`, `examples/HIST_CPU.jl:370`, `examples/HIST_CPU.jl:371`, `examples/HIST_CPU.jl:372`, `examples/HIST_CPU.jl:378`, `examples/HIST_CPU.jl:379`, `examples/HIST_CPU.jl:387`, `examples/HIST_CPU.jl:391`, `examples/HIST_CPU.jl:402`, `examples/HIST_CPU.jl:420`, `examples/HIST_CPU.jl:428`, `examples/HIST_CPU.jl:434`, `examples/HIST_CPU.jl:444`, `examples/HIST_CPU.jl:447`, `examples/HIST_CPU.jl:449`, `examples/HIST_CPU.jl:60`, `examples/HIST_CPU.jl:63`, `examples/HIST_CPU.jl:87`, `examples/HIST_CPU.jl:90`, `examples/gpu/rocm/HIST_ROCm.jl:120`, `examples/gpu/rocm/HIST_ROCm.jl:169`, `examples/gpu/rocm/HIST_ROCm.jl:184`, `examples/gpu/rocm/HIST_ROCm.jl:185`, `examples/gpu/rocm/HIST_ROCm.jl:216`, `examples/gpu/rocm/HIST_ROCm.jl:220`, `examples/gpu/rocm/HIST_ROCm.jl:274`, `examples/gpu/rocm/HIST_ROCm.jl:276`, `examples/gpu/rocm/HIST_ROCm.jl:279`, `examples/gpu/rocm/HIST_ROCm.jl:281`, `examples/gpu/rocm/HIST_ROCm.jl:313`, `examples/gpu/rocm/HIST_ROCm.jl:314`, `examples/gpu/rocm/HIST_ROCm.jl:367`, `examples/gpu/rocm/HIST_ROCm.jl:369`, `examples/gpu/rocm/HIST_ROCm.jl:371`, `examples/gpu/rocm/HIST_ROCm.jl:386`, `examples/gpu/rocm/HIST_ROCm.jl:389`, `examples/gpu/rocm/HIST_ROCm.jl:390`, `examples/gpu/rocm/HIST_ROCm.jl:391`, `examples/gpu/rocm/HIST_ROCm.jl:392`, `examples/gpu/rocm/HIST_ROCm.jl:408`, `examples/gpu/rocm/HIST_ROCm.jl:412`, `examples/gpu/rocm/HIST_ROCm.jl:423`, `examples/gpu/rocm/HIST_ROCm.jl:438`, `examples/gpu/rocm/HIST_ROCm.jl:452`, `examples/gpu/rocm/HIST_ROCm.jl:462`, `examples/gpu/rocm/HIST_ROCm.jl:465`, `examples/gpu/rocm/HIST_ROCm.jl:467`, `examples/gpu/rocm/HIST_ROCm.jl:81`, `examples/gpu/rocm/HIST_ROCm.jl:84`, `examples/gpu/rocm/HIST_ROCm.jl:96`, `src/Fields.jl:2467`, `src/Reductions.jl:1359`.

#### 015 — RULE.TEX.NO_HSCROLL

*Status:* open.

*Claim.* Two display blocks pack several equations onto one line behind \quad / \qquad instead of giving each its own row, which the rule forbids outright — and in one of them the correct form is on the same built page: lpnorm writes its two bases as rows of an aligned, while l2norm, three docstrings above it, strings them along one line.

*Proposed fix.* Give each equation its own row: in cross! break the three components onto three \\-separated rows of the existing gathered, and rewrite l2norm's block as an aligned with one row per base and the (\texttt{Grid3D}) / (\texttt{PointSet}) tags in a && column, matching lpnorm.

*Located at:* `src/FieldAlgebra.jl:1017`, `src/FieldAlgebra.jl:1018`, `src/Reductions.jl:932`, `src/Reductions.jl:934`.

#### 002 — open reader, no rule

*Status:* open.

*Claim.* An ORIENTATION is used throughout and declared nowhere. ARCHITECTURE Section 2's statement of the fiber's structure is closed and exhaustive — one fixed orthonormal frame, indices neither raised nor lowered, 'no metric to carry because it is the identity' — but cross, curl, inverse_curl and det rest on the Levi-Civita symbol, which is the volume form and is an independent datum from the metric. No page says the frame is ORDERED, no page fixes epsilon_{123} = +1, and no page says that curl u and u x v are orientation-odd (pseudovector-valued) while being stored in the same VectorField type as orientation-even fields such as the velocity.

*Proposed fix.* Add one clause to Section 2's structure declaration: the single global frame is ORDERED, and its ordering fixes the orientation — equivalently epsilon_{123} = +1 — which is the datum cross, curl, inverse_curl and det use beyond the metric. Then note, once, that those four are the orientation-odd members of the surface, so a consumer reflecting its frame must flip them while the type system will not. The alternative, leaving the orientation implicit in the component expansions, is what the package does today and is why the datum is invisible to a reader who reads the declaration rather than the formulas.

*Located at:* `docs/ARCHITECTURE.md:88`, `docs/FORMALIZATION.md:181`, `src/DifferentialOperators.jl:1087`, `src/FiberSections.jl:695`, `src/FieldAlgebra.jl:1012`.

#### 004 — open reader, no rule

*Status:* open.

*Claim.* The CPU example names u x omega 'the Lamb vector', which is the NEGATIVE of the vector that name standardly denotes. The equation the example advances is correct — the rotational form is du/dt = u x omega - grad(p + |u|^2/2) + viscous, and the Leray projection removes the gradient — so only the name is wrong, but it is wrong by a sign, in a page a consumer reads to learn the method.

*Proposed fix.* Either name the quantity for what it is — 'the rotational-form nonlinearity u x omega', which needs no convention — or keep the name and write the sign, 'minus the Lamb vector omega x u'. Naming it after the transform that appears in the code is the safer of the two, since the example's other nonlinearity vocabulary is already neutral.

*Located at:* `examples/HIST_CPU.jl`.

#### 040 — open reader, no rule

*Status:* open.

*Claim.* Two admonition headings show their backticks as literal characters, so the reader meets a title reading 'The default `ESTIMATE` planner…' with the marks printed rather than the name set in code. (Outside the seven rules I was given; reported because it is visible on the page.)

*Proposed fix.* Write the two titles without backticks, or move the name out of the title.

*Located at:* `docs/src/api/Fields.md`, `src/Fields.jl:1006`, `src/Fields.jl:1307`, `src/Points.jl:349`.

### Withdrawn (3)

#### 027 — RULE.DOC.TERMS_DEFINED

*Status:* withdrawn: additive, waits for a re-baseline of docs/prose_shape.csv (e6e60d39).

*Claim.* A class of the package's own nouns is used before anything on this page defines it: a "values function", the "index-shuffle guard", the "safe polarity", "slab-threaded", and the "zero-mode views".

*Proposed fix.* Bind each in a clause at its first appearance on the page - a values function in the module map rather than under _fiberwise_pass!, a one-clause statement of what the index-shuffle guard would otherwise do, and a word on what a slab is before the map relies on it.

*Located at:* `docs/src/api/FiberSections.md`, `src/FiberSections.jl:157`, `src/FiberSections.jl:20`, `src/FiberSections.jl:280`, `src/FiberSections.jl:807`.

#### 118 — RULE.TEX.CODE_SPAN_JULIA

*Status:* withdrawn: the finding was wrong — its fix made the notation page contain what RULE.TEX.LEFTRIGHT bans (ec3ee922).

*Claim.* LaTeX macro names are set on the page as code-looking text — \imath, \bigl/\Bigl, \bigr/\Bigr, \left/\right, \lvert...\rvert — and a backtick span holds only well-formed Julia, which none of these is; in the same breath the page states that a code identifier never sits inside a math span and then puts one inside one through \texttt.

*Proposed fix.* Check whether the macro names sit in backticks and, if they do, take them out — a LaTeX command is not Julia. Then record the \texttt exception in the lead paragraph, since the page relies on it: a code name that must appear inside a formula is wrapped in \texttt.

*Located at:* `docs/src/notation.md:74`, `docs/src/notation.md`.

#### 142 — RULE.TEX.CODE_SPAN_JULIA

*Status:* withdrawn: additive, waits for a re-baseline of docs/prose_shape.csv (bd3f6267).

*Claim.* The layout is given as a monospace span that is not Julia: the optional-argument brackets are notation, so the span reads as code that could be typed and cannot be.

*Proposed fix.* Write the shapes out as the three Julia tuples they stand for, or state the rule in prose: the array has the three grid axes first and then one axis of length 3 per tensor order.

*Located at:* `docs/src/tutorial.md`.

### Disregarded — on a generated tooling page (16)

#### 088 — RULE.DOC.GRAMMAR

*Status:* disregarded: located only on a generated tooling page.

*Claim.* Every instrument's start and end condition is written as a label-colon fragment with no subject and no verb of its own — six sites, one class, the page's only statement of when an instrument runs.

*Proposed fix.* Write each as a sentence naming its subject: "The run starts when the owner asks for it." / "It ends when nothing is open after its last pass, or when the owner ends it." / "It ends after one pass over the change."

*Located at:* `docs/src/gbg-instruments.md`.

#### 091 — RULE.DOC.GRAMMAR

*Status:* disregarded: located only on a generated tooling page.

*Claim.* Every reader in the catalogue is described by a fragment rather than a sentence: the first three are verbless noun phrases and the last two are predicates with no subject, so the page's central content never states who does what.

*Proposed fix.* Give each entry a subject and a finite verb: 'The withheld reader is a scientist in the package's own fields, new to the package, who reads one page ...'; 'The plain_sense reader asks of each sentence whether it means anything.'

*Located at:* `docs/src/gbg-readers.md:25`, `docs/src/gbg-readers.md:39`, `docs/src/gbg-readers.md:62`, `docs/src/gbg-readers.md:87`, `docs/src/gbg-readers.md:91`.

#### 096 — RULE.DOC.GRAMMAR

*Status:* disregarded: located only on a generated tooling page.

*Claim.* Every entry in the third section closes with the same sentence said twice, and the second half is verbless and stops without a full stop.

*Proposed fix.* Emit one sentence, not two, and give it a finite verb: 'Nothing checks this rule; a session follows it while working.' Drop the restatement entirely, since the first clause already says it.

*Located at:* `docs/src/gbg-rules.md:599`, `docs/src/gbg-rules.md`.

#### 097 — RULE.DOC.GRAMMAR

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The line that closes all 92 entries is a participial fragment with neither subject nor finite verb.

*Proposed fix.* Write the clause out: 'A program checks this rule.' / 'A reader given nothing judges this rule, because deciding it needs meaning.'

*Located at:* `docs/src/gbg-rules.md:19`, `docs/src/gbg-rules.md:441`.

#### 098 — RULE.DOC.GRAMMAR

*Status:* disregarded: located only on a generated tooling page.

*Claim.* Several rule statements open with a verbless label and a colon, and one continues into a verbless list that ends in an equals sign used as prose.

*Proposed fix.* Lead with the clause: 'A claim the documentation makes is current: a rule cited by id names a rule that exists.' In the last one, write the list as a sentence - 'A denominator is derived, an absence has its arm, and a count of zero means the check is dead.'

*Located at:* `docs/src/gbg-rules.md:124`, `docs/src/gbg-rules.md:486`, `docs/src/gbg-rules.md:583`, `docs/src/gbg-rules.md:740`.

#### 104 — RULE.DOC.GRAMMAR

*Status:* disregarded: located only on a generated tooling page.

*Claim.* In several entries the reason paragraph restates the statement almost word for word, so the entry says the same thing twice and gives no reason at all.

*Proposed fix.* Give each of those four entries a reason that is not its statement - what goes wrong when the rule is broken - as the neighbouring entries do.

*Located at:* `docs/src/gbg-rules.md:373`, `docs/src/gbg-rules.md:431`.

#### 090 — RULE.DOC.SELF_CONTAINED

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The table carries the page's substance in columns whose meaning the prose never binds — "Decided by", "Fix passes" and above all "Here", whose three cells read "runs" and point somewhere the page never names.

*Proposed fix.* Say in the prose what each column asks before the table appears, and either spell the "Here" cell as the place it means — the directory a run's record is written to — or drop the column.

*Located at:* `docs/src/gbg-instruments.md:11`, `docs/src/gbg-instruments.md`.

#### 093 — RULE.DOC.SELF_CONTAINED

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The page's payload is a list of bare rule identifiers that nothing on the page binds, and the one pointer to the rulebook sits buried inside a single reader's paragraph rather than where the identifiers are first used.

*Proposed fix.* Bind 'the rules' at first use by naming the rulebook and where it lives, and link each identifier to its entry there — or give each reader's list a one-line gloss per rule instead of a bare id.

*Located at:* `docs/src/gbg-readers.md:71`, `docs/src/gbg-readers.md`.

#### 094 — RULE.DOC.SELF_CONTAINED

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The opening paragraph enumerates four things a reader may be given, one of which — the sibling pages — is carried by no row of the table below, so the enumeration and the catalogue cannot be matched against each other.

*Proposed fix.* Either drop 'the sibling pages' from the enumeration, or say in the same sentence which row carries it; if it is the 'every document and the source' bundle, name it so.

*Located at:* `docs/src/gbg-readers.md:8`.

#### 089 — RULE.DOC.TERMS_DEFINED

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The page names the machinery of a review in terms of art it never defines or links: the change guard, the checks, a verifier agent, a documentation fixer and a code fixer, a stage, a candidate, a pass and the owner.

*Proposed fix.* Bind each noun in the clause that first uses it — one sentence apiece — or link it to the page that defines it; the same applies to the fixer and verifier named in the table.

*Located at:* `docs/src/gbg-instruments.md:13`, `docs/src/gbg-instruments.md:14`, `docs/src/gbg-instruments.md:19`, `docs/src/gbg-instruments.md:29`, `docs/src/gbg-instruments.md:8`.

#### 092 — RULE.DOC.TERMS_DEFINED

*Status:* disregarded: located only on a generated tooling page.

*Claim.* Three terms of art carry the page's argument and none is defined in a clause or linked before its first use: the 'tag' a rule carries, the 'config' the package declares a field of expertise in, and 'Literate'.

*Proposed fix.* Bind each at first use: say what a tag is and where it is written; name the config file and the field it sets; gloss Literate in a clause ('Literate, which turns an example script into a page') or link it.

*Located at:* `docs/src/gbg-readers.md:10`, `docs/src/gbg-readers.md:62`, `docs/src/gbg-readers.md`.

#### 099 — RULE.DOC.TERMS_DEFINED

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The page names a dozen of its own machinery terms that it never defines, on the page or in its own glossary.

*Proposed fix.* Bind each on first use in the clause that needs it, or drop it: say what a question's items and exhibit are where the ASK rules first lean on them, quote the marker phrase, give the cap and the column as numbers, and introduce the gbg command once in the opening paragraph.

*Located at:* `docs/src/gbg-rules.md:108`, `docs/src/gbg-rules.md:15`, `docs/src/gbg-rules.md:630`, `docs/src/gbg-rules.md`.

#### 100 — RULE.DOC.TERMS_DEFINED

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The glossary sits after all 92 entries, so every term it defines is used dozens of times before the page defines it - and the labels the entries actually use are not the ones it defines.

*Proposed fix.* Put the glossary before the rule listing, and name the bundles in it with the exact labels the cover lines print, including the combined ones.

*Located at:* `docs/src/gbg-rules.md:498`, `docs/src/gbg-rules.md`.

#### 103 — RULE.TEX.CODE_SPAN_JULIA

*Status:* disregarded: located only on a generated tooling page.

*Claim.* Two code spans reach the reader as literal backtick characters, one of them empty and one around a name whose underscore has been eaten.

*Proposed fix.* Escape the name so the span survives the build, and print an empty default as a named value the reader can act on ('unset, no formalization document is named') rather than as an empty span.

*Located at:* `docs/src/gbg-rules.md`.

#### 102 — RULE.TEX.IMAGINARY

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The rule that fixes the imaginary unit shows it to the reader as raw LaTeX source rather than as an upright i, and in the same breath prints the bare form it forbids.

*Proposed fix.* Render the required form as mathematics so the reader sees the upright i, and set the forbidden and quoted commands as marked, monospaced source, so the page shows the contrast it is describing.

*Located at:* `docs/src/gbg-rules.md:575`, `docs/src/gbg-rules.md`.

#### 095 — open reader, no rule

*Status:* disregarded: located only on a generated tooling page.

*Claim.* The closing section is headed as a list of gaps and its single sentence denies that any exist, so the heading a reader came to read is answered by its own refutation and the section carries nothing.

*Proposed fix.* State the emptiness in the heading's own terms, or make the sentence answer it — 'No rule a reader decides is left unassigned: every one reaches a reader above.'

*Located at:* `docs/src/gbg-readers.md:95`.

### Fixed (18)

#### 012 — RULE.CIT.NO_INACCESSIBLE

*Status:* fixed in a50da561, 17907467.

*Claim.* docs/PERFORMANCE.md cites 'the handover' four times as the authority for what was asked, ordered and caught, and docs/FORMALIZATION.md cites CLAUDE.md as the authority for a documentation rule. Both documents are copied into docs/src and rendered, so a reader of the site is told that the reason for a measurement, or for a whole page's licence to use component notation, lives in a document they cannot open — a session handover that exists in no repository at all, and an operational file that is not published.

*Proposed fix.* Replace each 'the handover' with what the sentence is actually about — 'the queued item', 'the recorded plan', or simply state the fact without an attributing clause ('the transfer-only splice was refused because src/ had moved by nine files'). In FORMALIZATION.md attribute the coordinate-free preference to RULE.DOC.COORD_FREE, which the reader can reach on the rendered rules page, rather than to CLAUDE.md.

*Located at:* `docs/FORMALIZATION.md:20`, `docs/PERFORMANCE.md:1825`, `docs/PERFORMANCE.md:1851`, `docs/PERFORMANCE.md:1934`, `docs/PERFORMANCE.md:1941`.

#### 016 — RULE.DOC.GRAMMAR

*Status:* fixed in ef37990f, b23ea76f.

*Claim.* Four places on the page are not sentences: a duplicated tail left in the prose, a verbless noun phrase standing as a docstring's identity, a plural that does not agree, and a parenthesis opened inside a parenthesis so that the main clause never resumes.

*Proposed fix.* Delete the repeated '. for the factors)'. Give _kernel_storage a verb ('Return an array representative of the kernel's storage family; there is one method per storage class'). Write 'applied to all of the fibre components' (or 'to every fibre component'), and settle on one spelling of fibre/fiber, which the page currently uses both ways. In the Internal API paragraph, move the gloss of "gated" into its own sentence so the pair's relative clause sits next to the pair.

*Located at:* `docs/src/api/Convolution.md:72`, `docs/src/api/Convolution.md`, `src/Convolution.jl:2038`, `src/Convolution.jl:629`.

#### 022 — RULE.DOC.GRAMMAR

*Status:* fixed in 7a067447, 126d48c6.

*Claim.* Four sentences on the page have no subject and no verb. Two are the same sentence, standing alone as the second sentence of the laplacian and inverse_laplacian wrappers; the other two open an internal docstring and close another. Each is a compression of a real sentence rather than a short one, so each has to be reassembled by the reader before it says anything.

*Proposed fix.* Restore the verbs: 'The operator preserves the tensor order: a scalar, vector or tensor field gives a result of the same order.'; 'The pass is alias-safe by construction — …'; 'Every helmholtz_projection! method shares it.'

*Located at:* `docs/src/api/DifferentialOperators.md`, `src/DifferentialOperators.jl:1371`, `src/DifferentialOperators.jl:1459`, `src/DifferentialOperators.jl:536`.

#### 025 — RULE.DOC.GRAMMAR

*Status:* fixed in c754b888, 7ae05925.

*Claim.* A class of identity paragraphs is a verbless noun phrase punctuated as a sentence; the page's introspection helpers and its two constants all open this way.

*Proposed fix.* Give each identity a verb, in the register the page already uses elsewhere ("Return the number of stored scalar components ...", "Hold the element count below which ...").

*Located at:* `docs/src/api/FiberSections.md`, `src/FiberSections.jl:146`, `src/FiberSections.jl:156`.

#### 036 — RULE.DOC.GRAMMAR

*Status:* fixed in 2234605d, c6752cf7.

*Claim.* A run of docstrings opens with a noun phrase instead of a sentence: the leading identity has no finite verb, so it does not say that the function returns the thing, only names it.

*Proposed fix.* Lead each with a verb, in the form the rest of the page already uses: 'Return one component of a section's storage as a three-dimensional array over the grid.'

*Located at:* `docs/src/api/Fields.md`, `src/Fields.jl:1432`, `src/Fields.jl:2913`, `src/Fields.jl:2973`.

#### 044 — RULE.DOC.GRAMMAR

*Status:* fixed in 6f6313f2, 6ee25691.

*Claim.* The first thing the page says about the package is a noun phrase with no finite verb: a long list of modifiers ending in a full stop, saying nothing about the fields it names.

*Proposed fix.* Give it a predicate: 'GBGPeriodicFields carries real-valued scalar, vector and second-order-tensor fields on three-dimensional rectangular periodic domains, in physical-space and real-to-complex spectral representations, on CPU and GPU array backends, with HDF5 persistence.'

*Located at:* `src/GBGPeriodicFields.jl:12`.

#### 049 — RULE.DOC.GRAMMAR

*Status:* fixed in 8356ae05, 7788af8c, 09d7dde4, cd85a90a.

*Claim.* The identity sentence of every type and constant on the page is a verbless noun phrase. Six docstrings open with a heading-like fragment terminated by a full stop rather than a sentence, so the first thing a cold reader meets in each is a label he must parse as prose without a verb to tell him what the thing does.

*Proposed fix.* Give each identity a verb: 'A PointTraversalOrder is a validated permutation of 1:M that says which point each unit of work handles.' The compactness survives the verb.

*Located at:* `docs/ARCHITECTURE.md:921`, `docs/ARCHITECTURE.md:955`, `docs/src/api/Interpolation.md`, `src/Interpolation.jl:202`, `src/Interpolation.jl:383`.

#### 050 — RULE.DOC.GRAMMAR

*Status:* fixed in 5af317b9, 96df39fb.

*Claim.* Four sentences of running prose are verbless noun-stacks rather than sentences. Unlike the type identities above these sit mid-paragraph, where a fragment reads as a line of notes dropped into the text; one of them carries a real claim — that the two scheme families share one adjointness contract — in a form with nothing to assert it.

*Proposed fix.* Restore the verb: 'The two families take the same verbs and honour one adjointness contract, with the one non-uniformity documented below'; 'This is a host-side helper for the spline-weight construction'; 'It is pure scalar arithmetic and kernel-safe'.

*Located at:* `docs/src/api/Interpolation.md`, `src/Interpolation.jl:121`, `src/Interpolation.jl:284`, `src/Interpolation.jl:416`.

#### 007 — RULE.DOC.HOME_ORDER

*Status:* fixed in 22133f33.

*Claim.* Four function docstrings put a caveat admonition immediately after the identity sentence, ahead of the when-to-use paragraph and the argument list, where the rule places caveats last in the home's prose. In two of them the admonition also separates the in-place steer from the identity it belongs to, so a reader meets a nonlocality warning or an alpha/beta exception before learning what the operation's arguments are.

*Proposed fix.* Move each block below the argument list and the formula, so it is the last prose block: convolve!'s kernel-composition note, combine!'s alpha/beta-exception note, inverse_laplacian!'s nonlocality warning and helmholtz_projection!'s. In inverse_laplacian! and helmholtz_projection! the in-place steer then follows the identity directly, as it does everywhere else in the module.

*Located at:* `src/Convolution.jl:947`, `src/DifferentialOperators.jl:1419`, `src/DifferentialOperators.jl:1505`, `src/FieldAlgebra.jl:522`.

#### 019 — RULE.DOC.RETURNS

*Status:* fixed in bd88cd0b, fa45abcb, c8200460.

*Claim.* translation_kernel! never says what it returns, and two of the four materialize_kernel methods name neither the returned type nor an arrow.

*Proposed fix.* Add one sentence to translation_kernel! — 'Returns kernel' — placed before the argument list. Give the ProductKernel and RadialKernel methods of materialize_kernel the arrow the builders use (-> StoredKernel), or name StoredKernel in their identity sentence as the SeparableKernel method already does.

*Located at:* `docs/src/api/Convolution.md`.

#### 021 — RULE.DOC.RETURNS

*Status:* fixed in 0168e6c5, 7733c600.

*Claim.* inverse_curl! is the one public in-place form on the page that never says what it returns: its identity sentence names the destination it writes but not the value that comes back, and its signature carries no arrow. Its seven siblings all close with 'returning destination', so a reader who has learned that convention from them is left guessing precisely where the page breaks it. Every one of the ten internal ! methods is silent the same way.

*Proposed fix.* Close inverse_curl!'s identity sentence as its siblings do: 'Recover the divergence-free vector field whose curl is field, writing it into destination and returning destination.' Give the internal mode-pass methods the same one clause.

*Located at:* `docs/src/api/DifferentialOperators.md`, `src/DifferentialOperators.jl:535`.

#### 023 — RULE.DOC.SELF_CONTAINED

*Status:* fixed in 542fd4a5, dfa2e1dd.

*Claim.* Two symbols are used and bound nowhere on the page. $N$ appears only inside the cost comparison $O(N)$ against $O(N^3)$, so whether it counts grid points, points per axis or modes — and therefore whether the comparison is a factor of $N^2$ or something else — cannot be decided from the page. $\Omega$ appears only under the integral sign of the solvability condition, with the box it denotes named in words in the same clause but never tied to the glyph.

*Proposed fix.* Bind both at first use: 'costs $O(N)$ in the grid size $N$ per axis, or a closure, rather than the $O(N^3)$ coefficients of a stored kernel', and 'the periodic box $\Omega$'.

*Located at:* `docs/src/api/DifferentialOperators.md`.

#### 020 — RULE.DOC.TERMS_DEFINED

*Status:* fixed in d95ea0f9, f717ec42, a0d57a63.

*Claim.* The page leans five times on "invariant 5" — a numbered rule of the package that it never states — to carry the one distinction the whole module turns on: which wavenumber family an operator applies. A reader of this page alone is told the family is 'the one of invariant 5' and has nowhere on the page to look the number up; the numbering is also unfollowable at the REPL, where the docstrings are read.

*Proposed fix.* Drop the number and keep the clause: write 'the derivative wavenumber family — zeroed at an even axis's Nyquist frequency, unlike the true squared wavenumber the Laplacian uses' at each site, which is already the page's own wording, and let the module docstring's Nyquist paragraph be the one home for the distinction.

*Located at:* `docs/DECISIONS.md:2956`, `docs/src/api/DifferentialOperators.md`, `src/DifferentialOperators.jl:1194`, `src/DifferentialOperators.jl:802`.

#### 052 — RULE.TEX.CODE_SPAN_JULIA

*Status:* fixed in d16b5319, 203f772a, c18b7428, 0104779a, aec803bb.

*Claim.* The TurTLE weight name is written as a code span holding a name template rather than a name: beta_n{n}_m{m} is not well-formed Julia — the braces are metavariables to be substituted with the two parameters, not syntax — so the span promises a symbol the reader could type and gives him one that does not parse.

*Proposed fix.* Write the template as prose or as LaTeX with the substitution shown — 'TurTLE's beta_n<n>_m<m> weights, with n and m the two parameters' — or give the concrete name for the default, keeping the backticks for something that parses.

*Located at:* `docs/src/api/Interpolation.md`.

#### 053 — RULE.TEX.CODE_SPAN_JULIA

*Status:* fixed in 055c7552.

*Claim.* One admonition title carries its backticks onto the rendered page: the reader sees the two grave accents printed as characters around the word, because an admonition title is not parsed as Markdown. It is the only such title on the page — the other five are plain prose — so it reads as a typo rather than as a convention.

*Proposed fix.* Drop the backticks from the title — 'NUFFT is deliberately not persistable' — and leave the code span to the body, where it renders.

*Located at:* `src/Interpolation.jl:2010`.

#### 136 — RULE.TEX.CODE_SPAN_JULIA

*Status:* fixed in dadd4358.

*Claim.* Asymptotic cost is written as a code span in some places and as mathematics in others, so the same notation renders two ways on one page.

*Proposed fix.* Write every asymptotic cost as mathematics — $O(1)$, $O(N)$ and $O(\text{shells})$ — and put the tensor order in math there too, $R = 2$, matching $R \le 2$ elsewhere.

*Located at:* `docs/TESTING.md:275`, `docs/TESTING.md:334`, `docs/src/testing.md:275`, `docs/src/testing.md:334`.

#### 119 — RULE.TEX.IMAGINARY

*Status:* fixed in dcfc9b38.

*Claim.* The row that teaches the upright-versus-italic distinction cannot demonstrate it: the upright unit is set as mathematics, while both counterexamples — the letter the reader is told not to write italic, and the letter freed for indices — are written outside any math span, so on the page they render in the same body face and the contrast the row rests on is invisible.

*Proposed fix.* Set both letters as mathematics in these clauses, so the page shows the contrast it asserts: never a bare italic $i$, and writing the unit upright frees $i$ for use as an index.

*Located at:* `docs/ARCHITECTURE.md:1096`, `docs/ARCHITECTURE.md:475`, `docs/ARCHITECTURE.md:490`, `docs/ARCHITECTURE.md:491`, `docs/ARCHITECTURE.md:894`, `docs/ARCHITECTURE.md:895`, `docs/DECISIONS.md:1015`, `docs/DECISIONS.md:238`, `docs/DECISIONS.md:2955`, `docs/DECISIONS.md:342`, `docs/DECISIONS.md:458`, `docs/DECISIONS.md:520`, `docs/DECISIONS.md:522`, `docs/DECISIONS.md:718`, `docs/DECISIONS.md:768`, `docs/DECISIONS.md:784`, `docs/DECISIONS.md:798`, `docs/FORMALIZATION.md:240`, `docs/FORMALIZATION.md:246`, `docs/FORMALIZATION.md:254`, `docs/FORMALIZATION.md:287`, `docs/FORMALIZATION.md:289`, `docs/FORMALIZATION.md:298`, `docs/FORMALIZATION.md:306`, `docs/FORMALIZATION.md:327`, `docs/FORMALIZATION.md:329`, `docs/FORMALIZATION.md:335`, `docs/FORMALIZATION.md:339`, `docs/FORMALIZATION.md:355`, `docs/FORMALIZATION.md:415`, `docs/FORMALIZATION.md:422`, `docs/FORMALIZATION.md:423`, `docs/FORMALIZATION.md:429`, `docs/FORMALIZATION.md:502`, `docs/FORMALIZATION.md:50`, `docs/FORMALIZATION.md:755`, `docs/FORMALIZATION.md:756`, `docs/FORMALIZATION.md:91`, `docs/FORMALIZATION.md:96`, `docs/FORMALIZATION.md:97`, `docs/TESTING.md:687`, `docs/src/notation.md:12`, `docs/src/notation.md:13`, `docs/src/notation.md`, `src/Convolution.jl:1909`, `src/Convolution.jl:1914`, `src/DifferentialOperators.jl:1108`, `src/DifferentialOperators.jl:1109`, `src/DifferentialOperators.jl:1115`, `src/DifferentialOperators.jl:1116`, `src/DifferentialOperators.jl:1117`, `src/DifferentialOperators.jl:114`, `src/DifferentialOperators.jl:118`, `src/DifferentialOperators.jl:1191`, `src/DifferentialOperators.jl:1267`, `src/DifferentialOperators.jl:1272`, `src/DifferentialOperators.jl:381`, `src/DifferentialOperators.jl:453`, `src/DifferentialOperators.jl:536`, `src/DifferentialOperators.jl:579`, `src/DifferentialOperators.jl:712`, `src/DifferentialOperators.jl:800`, `src/DifferentialOperators.jl:807`, `src/DifferentialOperators.jl:808`, `src/DifferentialOperators.jl:901`, `src/DifferentialOperators.jl:908`, `src/DifferentialOperators.jl:909`, `src/Fields.jl:1757`, `src/Interpolation.jl:1338`, `src/Interpolation.jl:1339`, `src/Interpolation.jl:1340`, `src/Interpolation.jl:1364`.

#### 001 — open reader, no rule

*Status:* fixed in e3484305, a037111e, 0d6b4d71, 9cf3a4f4, c38643f1, 309070eb, f7ceb305.

*Claim.* The slot the derivative index occupies in a gradient is declared one way in the architecture and the opposite way everywhere the components are written out. ARCHITECTURE Section 2 types the gradient into T*-Omega tensor E, fiber R^3 tensor V — the cotangent factor FIRST — while gradient!, divergence!, symmetric_gradient! and FORMALIZATION all put the derivative index LAST: (grad u)_{ij} = d_{x_j} u_i, and the tensor divergence contracts the SECOND slot, (div A)_i = d_{x_j} A_{ij}. The two orderings are not interchangeable: under Section 2's reading the tensor divergence would have to contract the first slot, so a reader who takes the architecture's typing literally derives the transpose of what the package computes.

*Proposed fix.* In ARCHITECTURE Section 2 write the codomain as E tensor T*-Omega, fiber V tensor R^3, and add the clause that fixes it against the code: the derivative index is the LAST fiber index, so (grad u)_{ij} = d_{x_j} u_i and the divergence contracts that last slot. The alternative — keeping T*-Omega tensor E and transposing the operators — is not available, the current index order being the one the tests, the fiber-last layout and the consumer all use.

*Located at:* `docs/ARCHITECTURE.md:81`, `docs/ARCHITECTURE.md:85`, `docs/FORMALIZATION.md:335`, `src/DifferentialOperators.jl:790`, `src/DifferentialOperators.jl:891`.
