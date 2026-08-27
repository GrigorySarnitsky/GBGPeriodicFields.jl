// THE DISMISSAL AUDIT — the half of /bug-hunt that the witness runner cannot cover. Ported from
// GBGIsotropicTurbulence 2026-08-27 (mechanism only).
//
// `witnesses.jl` proves that every CONFIRMED finding behaves as claimed. It says nothing about the
// findings that were never confirmed. Those verdicts — NOT-REPRODUCED, WITNESS-WRONG, ALREADY-COVERED
// — are judgement calls made by one agent under time pressure, and then they are FILED. Under
// /bug-hunt's design the instrument runs once and the verification loops over what it confirmed, so a
// wrong dismissal is not merely unexamined: nothing will ever look at it again.
//
// PF's own bug-hunt.md states the rule — "record the dismissal reason; do not quietly re-open it next
// round" — and had no mechanism behind it, which is the exact shape of every defect this pair of
// instrument sets has produced this week: the rule written down in the same tree, and read as though
// its presence were compliance.
//
// IT MEASURED WHAT THE MISSING AUDITOR COSTS. Two dismissals from one of its rounds:
//   * "correct on the current tree — a test-coverage gap, not a runtime defect."  It was a BLOCKER:
//     the read checked one of two epochs, so the exact mutation the design existed to catch was the
//     one it could not see.
//   * "sanctioned by the supertype contract."  A sibling operation hard-errored on the same input
//     while this one returned a silent default that sat ABOVE another scheme's tighter limit.
// Both surfaced only because a later hunt happened to re-raise them. With no later hunt, nothing
// would have.
//
// THE DEFAULT VERDICT IS UNSAFE, and the asymmetry is why: a wrongly-dismissed defect is silent and
// permanent, while a wrongly-upheld one costs one more look.
//
// Args: { repo, dismissals: [{title, location, claim, verdict, reasoning}] }
//   The array is what hunt.js returns as `dismissed`, so the two compose directly.
export const meta = {
  name: 'bug-hunt-dismissals',
  description: 'Re-examine every candidate a hunt dismissed, defaulting to "the dismissal is unsafe"',
  phases: [{ title: 'Audit dismissals' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo
const ITEMS = A.dismissals || []
if (!REPO) throw new Error('needs { repo }')
if (!ITEMS.length) throw new Error('needs a non-empty dismissals array — an EMPTY audit is not a clean one, and a run over nothing must not report success')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    title: { type: 'string' },
    verdict: { type: 'string', enum: ['DISMISSAL-SOUND', 'UNSAFE', 'DISMISSAL-WRONG'] },
    evidence: { type: 'string', description: 'quoted lines from the CURRENT tree that settle it, <= 70 words' },
    what_would_bite: { type: 'string', description: 'if UNSAFE or DISMISSAL-WRONG: the concrete call and input that misbehaves' },
  },
  required: ['title', 'verdict', 'evidence'],
}

phase('Audit dismissals')
const out = await parallel(ITEMS.map((d, i) => () => agent(
`A defect hunt over GBGPeriodicFields — a Julia library of real-valued scalar/vector/tensor fields on
3D periodic domains, physical and spectral representations, CPU and GPU — raised this candidate and
then DISMISSED it. You are re-examining the DISMISSAL. You are not the agent who made it and you owe
it nothing.

  claim:      ${d.title}
  location:   ${d.location || '?'}
  mechanism:  ${d.claim || '(not recorded)'}
  verdict:    ${d.verdict || '(not recorded)'}
  reasoning:  ${d.reasoning || d.observed || '(not recorded)'}

Read the CURRENT tree at ${REPO} and decide:

  DISMISSAL-SOUND — the claim is genuinely not a defect and you can SHOW why from the code. Quote the
                    lines that settle it.
  UNSAFE          — you cannot establish that it is not a defect. THIS IS YOUR DEFAULT.
  DISMISSAL-WRONG — it IS a defect. Name the call and the input that misbehaves.

WHY THE DEFAULT IS UNSAFE: a wrongly-dismissed defect is silent and permanent, because nothing
revisits a filed dismissal; a wrongly-upheld one costs one more look. "I could not confirm it is fine"
is UNSAFE, never waved through.

THREE DISMISSAL SHAPES THAT WERE WRONG BEFORE — two from this instrument's history in the sibling
package, one from PF's own:

  * "correct on the current tree — a test-coverage gap, not a runtime defect." Check the CLAIM, not
    whether a test exists. One such dismissal hid a blocker.
  * "sanctioned by the contract / deliberate by design." A recorded arrangement is not evidence that
    it is right. If a sibling operation handles the same situation differently, that asymmetry IS the
    finding, and "it is documented" does not answer it. PF is dense with recorded decisions, so this
    shape is the likeliest one here — but note the converse: PF's deliberate absences (no field×field
    multiply in spectral representation, no tensor order above 2, no time or physics) ARE design and
    are documented as such, so check the docstring before treating an absence as a defect.
  * "the suite would catch it." Only true if a test actually asserts it. Grep for the assertion.

Do not hunt for anything else. Your scope is this one claim.`,
  { label: `dismissal:${(d.title || '?').slice(0, 34)}`, phase: 'Audit dismissals',
    schema: SCHEMA, agentType: 'general-purpose' })
  .then(v => ({ ...v, index: i + 1 }))))

const verdicts = out.filter(Boolean)
// A dead auditor leaves its dismissal UNAUDITED. Counting it as upheld would make the instrument
// safest exactly when it is least alive, which is the inversion every other lane here guards against.
const dead = ITEMS.length - verdicts.length
const tally = {}
for (const v of verdicts) tally[v.verdict] = (tally[v.verdict] || 0) + 1
for (const v of verdicts) log(`${String(v.index).padStart(2, '0')}  ${v.verdict.padEnd(16)} ${(v.title || '').slice(0, 80)}`)
log(`TALLY: ${JSON.stringify(tally)}`)
if (dead) log(`!! ${dead} auditor(s) DIED — that many dismissals are UNAUDITED, not upheld`)

const reopened = verdicts.filter(v => v.verdict !== 'DISMISSAL-SOUND')
if (reopened.length) {
  log(`!! ${reopened.length} dismissal(s) DO NOT HOLD — these go back on the finding list:`)
  for (const v of reopened) log(`   !! [${v.verdict}] ${v.title} — ${v.what_would_bite || v.evidence}`)
}
return { tally, verdicts, reopened, dead, complete: dead === 0 && reopened.length === 0 }
