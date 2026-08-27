// /audit-changes — WERE THESE EDITS JUSTIFIED, AND DID THEY SILENTLY CHANGE BEHAVIOUR?
// Ported from GBGIsotropicTurbulence 2026-08-27 (mechanism theirs; the lanes are PF's own).
//
// THE FOURTH INSTRUMENT, AND IT AUDITS A DIFFERENT OBJECT. /check-docs and /check-consistency audit
// PROSE; /bug-hunt audits CODE. This audits CHANGES to code — it reads the DIFF, not the tree.
//
// The distinction is what makes it non-redundant: an edit can be a CORRECT FIX and still be wrong to
// make — wider than the defect required, changing a default, rejecting a workflow that used to be
// legitimate, breaking a contract the fix did not need to touch. Neither the code nor the fix looks
// wrong in isolation, which is exactly why a hunt cannot find it. A hunt reads code; this reads edits.
//
// IT MEASURED THE GAP AGAINST ITS OWN WITNESS GATE: the witnesses reported NEWLY BROKEN = 0 while two
// regressions were live and confirmed by hand. A witness exists only for a defect the hunt FOUND, so a
// regression introduced by a FIX is invisible to it. PF has the same hole — test/regressions/ holds
// witnesses for found defects and nothing else.
//
// Args: { repo, diff, claims, strength }
//   diff   — a file holding `git diff <base>..HEAD -- src test docs`.
//   claims — optional file of `git log --format="%h %s" <base>..HEAD`; only claim-versus-edit reads it.
export const meta = {
  name: 'audit-changes',
  description: 'Audit a change set: was each edit justified, and did it silently alter behaviour that worked before?',
  phases: [{ title: 'Audit' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo, DIFF = A.diff, CLAIMS = A.claims
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'
if (!REPO || !DIFF) throw new Error('needs { repo, diff }')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    lane: { type: 'string' },
    verdict: { type: 'string', enum: ['CLEAN', 'CONCERNS'] },
    concerns: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        title: { type: 'string' },
        severity: { type: 'string', enum: ['serious', 'notable', 'minor'] },
        justified: { type: 'string', enum: ['yes', 'no', 'unclear'],
                     description: 'was the edit proportionate to the defect it claims to fix' },
        location: { type: 'string', description: 'file:line, and the hunk' },
        previously_worked: { type: 'string', description: 'the concrete call or input that was valid BEFORE and is not now, or "" if none' },
        evidence: { type: 'string', description: 'quoted from the diff or the tree — an assertion with no quotation is not a concern' },
      },
      required: ['title', 'severity', 'justified', 'location', 'evidence'],
    } },
  },
  required: ['lane', 'verdict', 'concerns'],
}

// PF's lanes. The kinds are IT's; the anchors and examples are PF's, because a lane that names another
// package's symbols would send every reader hunting for things that are not here.
const LANES = [
  { key: 'free-reader', brief: `NO LIST. Read the diff and the current code and say what troubles you about these CHANGES. Every other lane here works from a list somebody wrote down, and a list is a hypothesis about where the problems are. Do not work through a checklist; if you catch yourself doing so, go back to reading. You are held only to the panel's question — was each change justified, and did it silently alter behaviour for input that previously worked.` },

  { key: 'executing', anchor: true, brief: `YOU RUN THINGS. Every other lane READS, and that is this design's central flaw: the instruments these edits came from are founded on "a static claim about code is a hypothesis; the only admissible evidence is a program that fails", and the audit of them was built out of readers. So an edit justified by a MEASUREMENT written in a comment — "allocates nothing", "bitwise-identical", "2.7-6.5x", "free at 256^3", "0 bytes" — would be certified by an agent that read the comment.
    RUN THE MEASUREMENTS. PF is unusually good for this because its claims are executable: \`julia --project -e 'using Pkg; Pkg.test()'\` for the gate; \`test/allocations.jl\` for any "allocation-free" claim; \`test/pass_audit.jl\` for any traffic claim; \`test/method_parity.jl\` for any "the method set is unchanged" claim; and a two-line script for any numeric claim in a comment. If an edit asserts a number, produce that number.` },

  { key: 'under-rejection', anchor: true, brief: `GUARDS THE DIFF REMOVES OR WEAKENS — the direction that fails SILENTLY. Its dual, over-rejection, has an obvious symptom: an over-strict guard throws in your face. A removed or weakened guard returns a WRONG NUMBER instead. Enumerate every check, assertion, throw, or narrowing the diff deletes, relaxes, or moves later, and for each ask what input now reaches code that previously could not. PF's compatibility checks are the place to look — \`_check_field_domain_compatibility\`, \`_check_same_domain\`, \`_check_contractible\`, \`_check_multipliers_compatibility\`, \`_check_owned_storage\` — plus any \`throw\` that became a fallback.` },

  { key: 'over-rejection', brief: `NEWLY REJECTED USAGE. Enumerate every validation the diff ADDS, then for EACH ask whether that input was previously valid and useful for something legitimate. A validation that rejects a genuine workflow is a regression dressed as a safety improvement. Judge each on whether a consumer could reasonably have been doing it — PF's own history has the shape: refusing a grid, a tensor order, or a storage combination forecloses a study, and PF's stated rule is that an absence must encode MATHEMATICS, not convenience.` },

  { key: 'behaviour-change', anchor: true, brief: `SILENT BEHAVIOUR CHANGE. For input that was valid and worked BEFORE these edits, does the package now compute a different number, take a different branch, or return a different result? Trace each edit that touches a COMPUTATION rather than a validation. Decide, per edit, whether an existing run's output changes and by how much. Bitwise questions belong here: PF asserts bitwise thread-count invariance on CPU and tolerance across backends, so an edit that alters an accumulation order, an association, or a fused pass changes numbers even when it looks like a refactor.` },

  { key: 'invariants', anchor: true, brief: `PF'S OWN INVARIANTS, from CLAUDE.md, which are numbered and binding. Check each edit against them: (1) the public method set is the spec and deliberate absences encode validity; (3) fiber-last layout, component slices contiguous; (4) FFT normalization, a physical constant touching ONLY the zero mode; (5) the Nyquist split between derivative and squared wavenumbers, deliberately not unified; (6) no scalar indexing of device arrays, allocate through similar/similar_field; (9) aliasing safe by construction, sections own their storage; (10) alpha/beta semantics with exactly two named exceptions; (11) the transform input contract; (13) allocation-free is ENFORCED, not aspirational; (14) sections combine only within one precision and storage family, never by conversion. An edit that quietly relaxes one of these is the finding.` },

  { key: 'backend-portability', brief: `CPU-IDENTICAL, DEVICE-BROKEN. PF is GPU-first: storage is generic \`AbstractArray\` and scalar indexing of a device array is forbidden. \`Pkg.test()\` runs entirely on \`Array\`, and the GPU suite is opt-in — so an edit can be bit-identical on CPU and broken on \`CuArray\`/\`ROCArray\` with nothing failing in the gate. Look for: a new scalar index, a host-side branch on device data, a \`copyto!\` that assumes host memory, an allocation inside a kernel, a captured Type in a closure a launch must accept, and anything reaching \`FFTW\` flags on a device path.` },

  { key: 'claim-versus-edit', brief: `CLAIM AGAINST EDIT — you ARE to read ${CLAIMS || '(no claims file supplied; use `git log` in the repo)'} first, unlike the other lanes. For each commit-message claim, find the hunk and check the edit does what the claim says, no more and no less. Flag edits no claim mentions (drive-by changes), claims describing an edit not present, and claims whose scope is narrower than the edit made. This lane exists because on this project the author is simultaneously the finder, the fixer and the reporter.` },

  { key: 'contract-drift', anchor: true, brief: `A DOCSTRING IS A PROMISE. For every changed line of prose, check the promise against the CODE — at HEAD for what the code does, and at the base commit for what the promise USED to be. Hunt the direction that hides: a claim edited to match behaviour that is itself wrong (documentation bent to fit code rather than code fixed to fit documentation), a caveat or warning deleted, a quantifier weakened ("always" to "usually", "exactly" to "approximately", "bitwise" to "to roundoff"), a guarantee that lost a condition. Quote the code line that settles each.` },

  { key: 'sweep-completeness', brief: `AN INCOMPLETE SWEEP. When one instance is edited the others usually need it too — a renamed argument, a changed default, a retired term, a formula corrected in one docstring and not its \`f\`/\`f!\` twin, a decision-log entry updated while the invariant list was not. PF states this rule as "a flagged instance is a sample of a class; fix the class, not the line", and it has been broken while written down. For every change in this diff, grep the corpus for the OTHER sites stating the same thing and report what was left behind.` },
]

const SELECTED = LANES
phase('Audit')
const results = await parallel(SELECTED.map(lane => () => agent(
`You are auditing a CHANGE SET in GBGPeriodicFields — a Julia library of real-valued scalar/vector/
second-order-tensor fields on 3D periodic domains, with physical and real-to-complex spectral
representations, on CPU and GPU. It is a math library: no time, no particles, no physics, by design.

THE PANEL'S QUESTION, and it is not a defect hunt:

    Was each change proportionate to the defect it claims to fix, and did it silently alter
    behaviour for input that previously worked?

An edit can be a correct fix and still be wrong to make. You are not asked what else is wrong with the
package — a finding that would have been true before this diff belongs to /bug-hunt, not here.

  repository: ${REPO}
  diff:       ${DIFF}
  claims:     ${CLAIMS || '(none supplied)'}

RULES:
- Read the diff FIRST and in full. Then read whatever of the tree you need to judge it.
- EVERY concern quotes the diff or the tree. An assertion with no quotation is not a concern.
- \`previously_worked\` is the field that matters most: name the concrete call or input that was valid
  BEFORE this diff and is not now. If you cannot name one, say so — that is a real answer.
- Deliberate absences are DESIGN here, not defects: no field-times-field multiply in spectral
  representation, no tensor order above 2, no concept of time or physics. Check the docstring before
  flagging one.
- Return CLEAN only if you genuinely found nothing. A lane that returns CONCERNS with an empty array
  is a contradiction and will be read as a dead lane.

YOUR LANE:
${lane.brief}

Return the structured object with lane="${lane.key}".`,
  { label: `audit:${lane.key}`, phase: 'Audit', schema: SCHEMA, agentType: 'general-purpose',
    ...(STRENGTH === 'economy' && !lane.anchor ? { model: 'sonnet' } : {}) })))

const live = results.filter(Boolean)
const dead = SELECTED.length - live.length
const all = live.flatMap(r => (r.concerns || []).map(c => ({ ...c, lane: r.lane })))
const serious = all.filter(c => c.severity === 'serious')
const unjustified = all.filter(c => c.justified === 'no')
const regressions = all.filter(c => (c.previously_worked || '').trim().length > 0)

for (const r of live) log(`${(r.lane || '?').padEnd(20)} ${r.verdict.padEnd(9)} ${(r.concerns || []).length} concern(s)`)
if (dead) log(`!! ${dead} lane(s) DIED — that many lenses are UNAPPLIED, not clean`)
log(`TOTAL: ${all.length} concern(s) — ${serious.length} serious, ${unjustified.length} judged unjustified, ${regressions.length} naming input that previously worked`)
for (const c of serious) log(`   !! [serious] ${c.lane}: ${c.title} — ${c.location}`)
for (const c of regressions) log(`   !! [regression] ${c.lane}: ${c.title} — previously worked: ${c.previously_worked}`)

// The gate that follows reads this. Every serious finding must be ANSWERED — fixed, refused with a
// reason, or escalated — and an absent disposition is a dropped finding.
return { concerns: all, serious, unjustified, regressions, deadLanes: dead, covered_paths: ['src', 'test', 'docs'] }
