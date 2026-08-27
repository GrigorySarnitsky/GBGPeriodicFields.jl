// Fix verification — the ACT auditor. Ported from GBGIsotropicTurbulence 2026-08-27 (its request
// under .claude/, mechanism only; IT's own scripts are shaped around its pile layout).
//
// WHY THIS EXISTS, and it is not a matter of taste. The panel's discipline section asks for closure
// "per hat and per finding number" and, until this script, nothing checked it — the fixer's own
// account of whether a CLASS was swept was taken at face value. IT measured that configuration and
// found ELEVEN OF THIRTEEN deficiencies in one round were LINE-ONLY: the flagged site fixed, the
// class still alive on surfaces the finding's own text had already named. The rule "a flagged
// instance is a sample of a class" was written down, known, quoted — and broken anyway. So the
// lesson is not to state the rule more firmly. Stating it does not work; measuring it does.
//
// This script is HALF of the pair, and the halves are given deliberately OPPOSITE information:
//   verify-fixes.js (here) audits an ACT and SEES the diff — it judges the edits themselves.
//   verify.js       audits a STATE and is BLIND to the diff — it re-reads the tree and asks only
//                   whether each defect is present now.
// A fix can satisfy one and fail the other, which is the point: seeing the diff catches a fix that
// edited the quoted line and nothing else; not seeing it catches a defect that was never a defect,
// or one re-introduced elsewhere.
//
// Args (absolute paths): { pile, repo, range, strength }
//   pile     — .claude/doc-review, holding the panel's banked NN-<key>.md findings files.
//   repo     — the repository root, for `git diff`.
//   range    — the git range covering the fix pass, e.g. "a1b2c3d..HEAD". REQUIRED: a lane with no
//              range would grade edits it cannot see and would pass everything.
//   strength — 'economy' (default: cheap model per lane) | 'full'. Consolidation is never economized.
export const meta = {
  name: 'verify-fixes',
  description: 'Grade a fix pass finding-by-finding against the panel pile, seeing the diff (HONORED / LINE-ONLY / …)',
  phases: [ { title: 'Verify fixes' } ],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const PILE = A.pile
const REPO = A.repo
const RANGE = A.range
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'

if (!PILE || !REPO || !RANGE) {
  throw new Error('verify-fixes needs { pile, repo, range }: without a range a lane grades edits it cannot see, and would certify everything.')
}

// The panel's hats, in its own order, so NN-<key>.md resolves.
// The lane list is an ARGUMENT. It defaults to the /check-consistency panel's hats, but any
// instrument that banks NN-<lane>.md findings can be verified by passing its own — which is what
// lets /check-docs be verified at all, its lanes being surfaces rather than hats. A hardcoded
// list here is also exactly what coverage.py exists to catch drifting from the panel's.
const PANEL_HATS = ['consistency-matrix','software-architect','spectral-methods-mathematician','differential-geometer',
              'gpu-kernel-practitioner','structure-consistency','latex-typesetter','api-user',
              'normalization-convention-auditor','citations-integrity','style-editor','cold-reader']
const HATS = (A.lanes && A.lanes.length) ? A.lanes : PANEL_HATS

const PHASE_NAME = 'Verify fixes'

// The panel's do-not-re-flag list must reach the VERIFIERS too, and it did not. A finding the owner
// already settled as NOT a defect is correctly left unfixed — so a verifier blind to that list grades
// it UNDONE, depresses the closure rate with noise, and invites a fix pass at something deliberately
// left alone. panel.js has read this file since it existed; the verifiers inherited none of it.
const ADJUDICATED = A.adjudicated
const ADJ_NOTE = ADJUDICATED ? `

ALREADY ADJUDICATED — READ THIS FIRST: \`${ADJUDICATED}\`. It lists findings previously settled as NOT
defects. Note the asymmetry: nothing merely FIXED is listed there, so a finding's ABSENCE from it proves nothing and is not evidence the finding is open. A banked finding covered by that file is NOT an open defect: mark it accordingly and say so in
your evidence rather than grading it as unfixed. Leaving it in the denominator makes closure
unreachable and can drive a fix at something the owner deliberately left alone.` : ''

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    hat: { type: 'string' },
    pile_file_read: { type: 'boolean', description: 'false if the findings file was absent or unreadable' },
    findings_in_file: { type: 'integer', description: 'how many findings the banked file contains — count them, do not estimate' },
    verdicts: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        finding: { type: 'string', description: 'the finding number and title as the banked file gives them' },
        verdict: { type: 'string', enum: ['HONORED','LINE-ONLY','NEW-DEFECT','SCOPE-CREEP','UNDONE','LAUNDERED'] },
        evidence: { type: 'string', description: 'the decisive diff hunk or the absence of one; quote it' },
        class_surfaces: { type: 'string', description: 'the other surfaces the FINDING\'S OWN TEXT names or implies, one file:line each, and whether the diff swept it. Enumerate from the finding, NEVER from the diff — the diff shows only where someone already looked. An empty or vague answer demotes HONORED to LINE-ONLY by rule.' },
      },
      required: ['finding','verdict','evidence','class_surfaces'],
    } },
  },
  required: ['hat','pile_file_read','findings_in_file','verdicts'],
}

const PREAMBLE = `You are auditing a FIX PASS on the documentation of GBGPeriodicFields, a Julia field-operation library. You are NOT re-reviewing the docs and you are NOT looking for new defects. You are grading, finding by finding, what the fixer actually DID against what a panel of reviewers actually ASKED.

You may and should use Bash to run \`git diff ${RANGE}\` (and \`git show\`, \`git log\`) inside ${REPO}, and Read/Grep to inspect the current files. Seeing the diff is the point of this lane.

THE VERDICTS, and only these:
- HONORED — the defect is gone AND its class was swept. This is the ONLY passing verdict.
- LINE-ONLY — the quoted site was fixed and the class was not. Grade this whenever the finding's own text names or implies other surfaces (another operator in the same family, the sibling f/f! docstring, the same convention on another page) and the diff does not touch them. THIS IS THE MOST COMMON REAL OUTCOME; do not talk yourself out of it.
- NEW-DEFECT — the edit introduced a fresh problem (a broken claim, a wrong formula, a dangling reference).
- SCOPE-CREEP — the edit ranges well beyond the finding, changing things nobody asked about.
- UNDONE — nothing in the diff addresses this finding.
- LAUNDERED — the TEXT asserting the problem was removed or softened rather than the problem being fixed. Deleting a claim that was wrong is a fix; deleting the sentence that revealed a wrong claim, and leaving the claim, is laundering.

HARD RULES:
- DEFAULT TO THE UNFAVOURABLE VERDICT. If you cannot find diff evidence that the class was swept, it is LINE-ONLY, not HONORED. If you cannot find any relevant edit, it is UNDONE. A lane that runs out of budget must fail safe, so never grade HONORED on the strength of a plausible story — grade it on a hunk you can quote.
- Grade EVERY finding in the banked file, in order. If the file holds twelve findings, return twelve verdicts.
- Count \`findings_in_file\` by actually counting the sections in the file. A zero count from a lane that should have found a file is read downstream as a DEAD LANE, not as a clean hat, so do not report zero unless the file is genuinely absent.
- \`class_surfaces\` is not optional prose, and it is enumerated FROM THE FINDING, NEVER FROM THE DIFF. The diff shows only where someone already looked, so reading the class off it cannot detect the failure this instrument exists to detect. Start from the finding's own words — the family it names, the sibling docstring, the convention it says appears elsewhere — list each surface as \`file:line\`, and say for each whether the diff swept it. An empty or hand-waving answer is DEMOTED TO LINE-ONLY MECHANICALLY, after you return, so there is nothing to be gained by leaving it thin.`

phase('Verify fixes')

// A CENSUS FIRST, so the denominator does not come from the party being measured. Each grading lane
// used to report `findings_in_file` about its own file — which is the same antipattern this
// instrument exists to correct one level down: asking the constrained party whether the constraint
// binds. A lane that grades 5 of 13 and reports findings_in_file=5 looks complete. One cheap agent
// now counts every pile file up front, and the graders are TOLD their expected count; a shortfall
// between that and the verdicts returned is under-grading, detected mechanically below.
// (IT's own verifier avoids this by taking the findings array as an argument — a better shape, but
// this script cannot read files, so an independent counting agent is the equivalent.)
const CENSUS_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: { counts: { type: 'array', items: {
    type: 'object', additionalProperties: false,
    properties: { file: { type: 'string' }, findings: { type: 'integer' }, exists: { type: 'boolean' } },
    required: ['file','findings','exists'] } } },
  required: ['counts'],
}
// A caller who counted the pile mechanically (a shell one-liner, a script) can pass the counts in as
// `findings_per_hat` and skip the census entirely — then NO agent is in the denominator's loop, which
// is strictly better than a trustworthy agent. IT's refinement on this, adopted 2026-08-27.
const OVERRIDE = A.findings_per_hat || null
const census = OVERRIDE ? null : await agent(
  `Count findings in each banked panel file. Do NOT judge them, do NOT read the repository — just count.

For each of these files under ${PILE}, read it and report how many distinct FINDINGS it contains
(sections headed "Finding N", "## N", or equivalent — count the finding sections, not the paragraphs):
${HATS.map((k, i) => `  ${String(i + 1).padStart(2, '0')}-${k}.md`).join('\n')}

If a file does not exist, report exists=false and findings=0. Return the structured object.`,
  { label: 'census', phase: PHASE_NAME, schema: CENSUS_SCHEMA, agentType: 'general-purpose', model: 'sonnet' })
const expected = {}
if (OVERRIDE) { for (const k of Object.keys(OVERRIDE)) expected[k] = OVERRIDE[k] }
else { for (const c of ((census && census.counts) || [])) expected[c.file] = c.findings }
if (!Object.keys(expected).length) log('!! no denominator: neither findings_per_hat nor a census result — under-grading CANNOT be detected this run')
// PARALLEL since 2026-08-27. These lanes were sequential only because the panel they follow was, and
// that was a token-budget decision the fleet has since outgrown. Nothing here wanted serialising: a
// verifier lane emits verdicts, not prose, so the per-agent output cap is not close, and there is no
// priority order to protect because closure needs every hat's findings graded, not the first few.
const numbered = HATS.map((key, i) => ({ key, nn: String(i + 1).padStart(2, '0') }))
const outcomes = await parallel(numbered.map(({ key, nn }) => () => agent(`${PREAMBLE}

YOUR LANE: the findings banked by the "${key}" hat.${ADJ_NOTE}

An independent census counted ${expected[`${nn}-${key}.md`] === undefined ? 'an unknown number of' : expected[`${nn}-${key}.md`]} findings in that file. Grade EVERY one; a shortfall is reported as under-grading.

1. Read the banked findings file: ${PILE}/${nn}-${key}.md
   If it does not exist, return pile_file_read=false, findings_in_file=0 and an empty verdicts array.
2. Inspect the fix pass: \`git -C ${REPO} diff ${RANGE}\` (and any narrower git/grep commands you need).
3. Grade EVERY finding in that file against the diff, by the verdicts above.

FIRST use the Write tool to bank your verdicts as markdown to ${PILE}/closure/${nn}-${key}.md — one\nsection per finding headed \`## Finding N\`, each carrying the verdict (HONORED / LINE-ONLY / NEW-DEFECT / SCOPE-CREEP / UNDONE / LAUNDERED), the evidence, and the class_surfaces answer. THEN return the structured\nobject with hat="${key}". The banked file is the durable record: a returned object can come back empty\nwhile the work was done, and an external coverage check can only see what was written.`,
  { label: `verify-fixes:${key}`, phase: 'Verify fixes', schema: SCHEMA, agentType: 'general-purpose',
    ...(STRENGTH === 'economy' ? { model: 'sonnet' } : {}) })))

const results = []
outcomes.forEach((r, i) => {
  const { key, nn } = numbered[i]
  // A lane that returned NOTHING AT ALL is dead — distinct from one that read an absent file, and
  // distinct again from one that graded findings. Concurrency makes this sharper: a barrier reports
  // every lane at once, so a hole no longer announces itself by a missing line in a running log.
  if (!r) { log(`${nn} ${key}: DEAD — no result`); return }
  results.push(r)
  const exp = expected[`${nn}-${key}.md`]
  const got = (r.verdicts || []).length
  const self = r.findings_in_file
  // Do not silently prefer the census: a lane whose own count disagrees with an independent
  // one is telling you something about the lane, and swallowing that discards the signal.
  if (exp !== undefined && self !== undefined && self !== exp)
    log(`${nn} ${key}: COUNT DISAGREEMENT — lane says ${self}, census says ${exp}`)
  if (exp !== undefined && got < exp) log(`${nn} ${key}: UNDER-GRADED ${got}/${exp} — the missing ${exp - got} are UNVERIFIED, not clean`)
  // Demote by RULE, not by the grader's judgement. The whole failure mode is a fixer (and then a
  // grader) producing a plausible account of a sweep that never happened, so HONORED has to be EARNED
  // by an enumerated class — at least one concrete file:line surface. Leaving this to the prompt would
  // leave it to the same agent whose laziness it exists to catch. Ported back from IT 2026-08-27.
  const v = r.verdicts || []
  for (const x of v) {
    if (x.verdict !== 'HONORED') continue
    const cs = (x.class_surfaces || '').trim()
    if (cs.length < 12 || !/[^\s]:\d+/.test(cs)) {
      x.verdict = 'LINE-ONLY'
      x.evidence = `[DEMOTED: HONORED claimed with no enumerated class surface] ${x.evidence || ''}`
    }
  }
  const honored = v.filter(x => x.verdict === 'HONORED').length
  log(`${nn} ${key}: ${v.length} graded, ${honored} HONORED${r.pile_file_read === false ? ' (no findings file)' : ''}`)
})

// Liveness before arithmetic: a lane that returned nothing while its file held findings is a DEAD
// AGENT, and averaging over it silently inflates the honored rate. Report it as a lane failure, not
// as a clean hat — that inversion is one of the two properties this instrument exists to preserve.
const live = results.filter(r => r && r.pile_file_read !== false)
const dead = results.filter(r => r && r.pile_file_read !== false && (!r.verdicts || r.verdicts.length === 0) && r.findings_in_file > 0)
const graded = live.flatMap(r => r.verdicts || [])
const tally = {}
for (const v of graded) tally[v.verdict] = (tally[v.verdict] || 0) + 1
const honoredRate = graded.length ? (tally['HONORED'] || 0) / graded.length : 0

log(`graded ${graded.length} findings across ${live.length} live lanes — ${Math.round(honoredRate * 100)}% HONORED`)
for (const k of Object.keys(tally).sort()) log(`  ${k}: ${tally[k]}`)
if (dead.length) log(`DEAD LANES (returned nothing over a non-empty findings file): ${dead.map(d => d.hat).join(', ')}`)

// The stopping rule is a PLATEAU, not a good round. IT's honored rate ran 43 -> 69 -> 76 -> 95 -> 93
// -> 90%: round 2 looked like progress while concealing eleven LINE-ONLYs. Three flat rounds within
// noise, with no dead lanes, is closure.
return { honoredRate, tally, graded: graded.length, deadLanes: dead.map(d => d.hat), results }
