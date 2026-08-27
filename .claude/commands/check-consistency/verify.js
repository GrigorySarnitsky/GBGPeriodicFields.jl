// Fix verification — the STATE auditor. The other half of the pair; see verify-fixes.js for why the
// pair exists and what it measured. Ported from GBGIsotropicTurbulence 2026-08-27, mechanism only.
//
// THIS LANE IS DELIBERATELY BLIND TO THE DIFF. It re-reads the CURRENT manuscript against the banked
// findings and asks one question per finding: is this defect present NOW? It is not told what was
// edited, and it must not look. That blindness is the whole value — a lane that can see the fix is
// prone to reading the intention off the diff and grading the intention. This one can only see the
// result, so it catches two things its sighted twin cannot: a "fix" that changed something else and
// left the defect standing, and a finding that was never a defect at all.
//
// It is therefore NOT a duplicate of verify-fixes.js and neither substitutes for the other. A finding
// can be HONORED by the diff and still PRESENT in the tree (the edit missed a second occurrence), or
// UNDONE by the diff and ABSENT from the tree (someone else fixed it, or it was an artifact).
//
// Args (absolute paths): { pile, full, siteonly, strength }
//   pile     — .claude/doc-review, holding the panel's banked NN-<key>.md findings files.
//   full     — the CURRENT manuscript of every page incl. the design docs (regenerate it first —
//              verifying against the manuscript the panel read would measure nothing).
//   siteonly — the current manuscript with the design docs withheld, for the two hats that had it.
//   strength — 'economy' (default) | 'full'.
export const meta = {
  name: 'verify-state',
  description: 'Re-read the current manuscript and ask, per banked finding, whether the defect is still present (blind to the diff)',
  phases: [ { title: 'Verify state' } ],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const PILE = A.pile
const FULL = A.full
const SITEONLY = A.siteonly || A.full
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'

if (!PILE || !FULL) {
  throw new Error('verify needs { pile, full }: a regenerated manuscript is the state being audited.')
}

// The lane list is an ARGUMENT. It defaults to the /check-consistency panel's hats, but any
// instrument that banks NN-<lane>.md findings can be verified by passing its own — which is what
// lets /check-docs be verified at all, its lanes being surfaces rather than hats. A hardcoded
// list here is also exactly what coverage.py exists to catch drifting from the panel's.
const PANEL_HATS = ['consistency-matrix','software-architect','spectral-methods-mathematician','differential-geometer',
              'gpu-kernel-practitioner','structure-consistency','latex-typesetter','api-user',
              'normalization-convention-auditor','citations-integrity','style-editor','cold-reader']
const HATS = (A.lanes && A.lanes.length) ? A.lanes : PANEL_HATS
// The two hats the panel gives the user-facing site without the design docs; their findings must be
// re-checked against the same substrate or a "still present" verdict means something different.
const SITEONLY_HATS = ['api-user','cold-reader']

const PHASE_NAME = 'Verify state'

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
    pile_file_read: { type: 'boolean' },
    findings_in_file: { type: 'integer', description: 'counted, not estimated' },
    states: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        finding: { type: 'string' },
        state: { type: 'string', enum: ['PRESENT','ABSENT','UNCLEAR','NEVER-A-DEFECT'] },
        evidence: { type: 'string', description: 'quote the current text that settles it' },
      },
      required: ['finding','state','evidence'],
    } },
  },
  required: ['hat','pile_file_read','findings_in_file','states'],
}

const PREAMBLE = `You are auditing the CURRENT STATE of the documentation of GBGPeriodicFields, a Julia field-operation library, against a list of defects a review panel banked earlier.

For each banked finding, answer exactly one question: IS THIS DEFECT PRESENT IN THE DOCUMENT I AM READING NOW?

HARD RULES — the first is what makes this lane worth running:
- DO NOT look at the diff, the git history, or any record of what was changed. Do not run git. Do not ask what was fixed. You are judging the text as it stands, and your blindness to the edits is deliberate: a lane that can see the intention tends to grade the intention.
- Read ONLY the manuscript named in your substrate below. Do not open src/, tests, or CLAUDE.md.
- DEFAULT TO THE UNFAVOURABLE VERDICT. If you cannot find the passage, or cannot tell whether the defect stands, answer UNCLEAR — never ABSENT. ABSENT requires you to have found the passage and seen that it is now correct.
- NEVER-A-DEFECT is available and you should use it when the banked finding misreads the document: the text it quotes does not say what the finding claims, or the claimed contradiction is not one. That verdict is as useful as the others — a panel is fallible and a fix pass that "fixed" a non-defect has damaged the docs.
- Count \`findings_in_file\` by counting the sections. A zero count where a file exists is read downstream as a DEAD LANE, not a clean hat.
- Quote the decisive CURRENT text in every evidence field. A verdict with no quotation is not evidence.`

phase('Verify state')

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
const outcomes = await parallel(numbered.map(({ key, nn }) => () => {
  const substrate = SITEONLY_HATS.indexOf(key) >= 0
    ? `The current user-facing site, design docs withheld: ${SITEONLY}`
    : `The current whole rendered site incl. the design docs: ${FULL}`
  return agent(`${PREAMBLE}

YOUR LANE: the findings banked by the "${key}" hat.${ADJ_NOTE}

An independent census counted ${expected[`${nn}-${key}.md`] === undefined ? 'an unknown number of' : expected[`${nn}-${key}.md`]} findings in that file. Grade EVERY one; a shortfall is reported as under-grading.

1. Read the banked findings file: ${PILE}/${nn}-${key}.md
   If it does not exist, return pile_file_read=false, findings_in_file=0 and an empty states array.
2. Read your substrate: ${substrate}
3. For EVERY finding in the banked file, in order, decide PRESENT / ABSENT / UNCLEAR / NEVER-A-DEFECT and quote the current text that settles it.

FIRST use the Write tool to bank your verdicts as markdown to ${PILE}/state/${nn}-${key}.md — one\nsection per finding headed \`## Finding N\`, each carrying the state (PRESENT / ABSENT / UNCLEAR / NEVER-A-DEFECT) and the quoted current text. THEN return the structured\nobject with hat="${key}". The banked file is the durable record: a returned object can come back empty\nwhile the work was done, and an external coverage check can only see what was written.`,
    { label: `verify:${key}`, phase: 'Verify state', schema: SCHEMA, agentType: 'general-purpose',
      ...(STRENGTH === 'economy' ? { model: 'sonnet' } : {}) })
}))

const results = []
outcomes.forEach((r, i) => {
  const { key, nn } = numbered[i]
  if (!r) { log(`${nn} ${key}: DEAD — no result`); return }
  results.push(r)
  const exp = expected[`${nn}-${key}.md`]
  const got = (r.states || []).length
  const self = r.findings_in_file
  // Do not silently prefer the census: a lane whose own count disagrees with an independent
  // one is telling you something about the lane, and swallowing that discards the signal.
  if (exp !== undefined && self !== undefined && self !== exp)
    log(`${nn} ${key}: COUNT DISAGREEMENT — lane says ${self}, census says ${exp}`)
  if (exp !== undefined && got < exp) log(`${nn} ${key}: UNDER-GRADED ${got}/${exp} — the missing ${exp - got} are UNVERIFIED, not clean`)
  const st = r.states || []
  const absent = st.filter(x => x.state === 'ABSENT').length
  log(`${nn} ${key}: ${st.length} checked, ${absent} ABSENT${r.pile_file_read === false ? ' (no findings file)' : ''}`)
})

const live = results.filter(r => r && r.pile_file_read !== false)
const dead = live.filter(r => (!r.states || r.states.length === 0) && r.findings_in_file > 0)
const checked = live.flatMap(r => r.states || [])
const tally = {}
for (const s of checked) tally[s.state] = (tally[s.state] || 0) + 1
const clearedRate = checked.length ? (tally['ABSENT'] || 0) / checked.length : 0

log(`checked ${checked.length} findings across ${live.length} live lanes — ${Math.round(clearedRate * 100)}% ABSENT`)
for (const k of Object.keys(tally).sort()) log(`  ${k}: ${tally[k]}`)
if (dead.length) log(`DEAD LANES (returned nothing over a non-empty findings file): ${dead.map(d => d.hat).join(', ')}`)

// Read this ALONGSIDE verify-fixes.js, never instead of it. The interesting cells are the
// disagreements: HONORED-but-PRESENT is a fix that missed an occurrence; UNDONE-but-ABSENT is
// usually a finding that was never a defect. Agreement on both is the only real closure.
return { clearedRate, tally, checked: checked.length, deadLanes: dead.map(d => d.hat), results }
