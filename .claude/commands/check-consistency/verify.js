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

const HATS = ['consistency-matrix','software-architect','spectral-methods-mathematician','differential-geometer',
              'gpu-kernel-practitioner','structure-consistency','latex-typesetter','api-user',
              'normalization-convention-auditor','citations-integrity','style-editor','cold-reader']
// The two hats the panel gives the user-facing site without the design docs; their findings must be
// re-checked against the same substrate or a "still present" verdict means something different.
const SITEONLY_HATS = ['api-user','cold-reader']

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
const results = []
for (let i = 0; i < HATS.length; i++) {
  const key = HATS[i]
  const nn = String(i + 1).padStart(2, '0')
  const substrate = SITEONLY_HATS.indexOf(key) >= 0
    ? `The current user-facing site, design docs withheld: ${SITEONLY}`
    : `The current whole rendered site incl. the design docs: ${FULL}`
  const prompt = `${PREAMBLE}

YOUR LANE: the findings banked by the "${key}" hat.

1. Read the banked findings file: ${PILE}/${nn}-${key}.md
   If it does not exist, return pile_file_read=false, findings_in_file=0 and an empty states array.
2. Read your substrate: ${substrate}
3. For EVERY finding in the banked file, in order, decide PRESENT / ABSENT / UNCLEAR / NEVER-A-DEFECT and quote the current text that settles it.

Return the structured object with hat="${key}".`
  const economized = STRENGTH === 'economy'
  const r = await agent(prompt, { label: `verify:${key}`, phase: 'Verify state', schema: SCHEMA,
                                  agentType: 'general-purpose', ...(economized ? { model: 'sonnet' } : {}) })
  results.push(r)
  const st = (r && r.states) || []
  const absent = st.filter(x => x.state === 'ABSENT').length
  log(`[${nn}/${HATS.length}] ${key}: ${st.length} checked, ${absent} ABSENT${r && r.pile_file_read === false ? ' (no findings file)' : ''}`)
}

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
