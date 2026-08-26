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
const HATS = ['consistency-matrix','software-architect','spectral-methods-mathematician','differential-geometer',
              'gpu-kernel-practitioner','structure-consistency','latex-typesetter','api-user',
              'normalization-convention-auditor','citations-integrity','style-editor','cold-reader']

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
        class_surfaces: { type: 'string', description: 'the other surfaces the finding named or implied, and whether each was swept — the whole basis of a LINE-ONLY verdict' },
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
- \`class_surfaces\` is not optional prose: name the other surfaces the finding reaches and say, for each, whether the diff swept it. A verdict of HONORED with an empty class_surfaces will be treated as LINE-ONLY.`

phase('Verify fixes')
const results = []
for (let i = 0; i < HATS.length; i++) {
  const key = HATS[i]
  const nn = String(i + 1).padStart(2, '0')
  const prompt = `${PREAMBLE}

YOUR LANE: the findings banked by the "${key}" hat.

1. Read the banked findings file: ${PILE}/${nn}-${key}.md
   If it does not exist, return pile_file_read=false, findings_in_file=0 and an empty verdicts array.
2. Inspect the fix pass: \`git -C ${REPO} diff ${RANGE}\` (and any narrower git/grep commands you need).
3. Grade EVERY finding in that file against the diff, by the verdicts above.

Return the structured object with hat="${key}".`
  const economized = STRENGTH === 'economy'
  const r = await agent(prompt, { label: `verify-fixes:${key}`, phase: 'Verify fixes', schema: SCHEMA,
                                  agentType: 'general-purpose', ...(economized ? { model: 'sonnet' } : {}) })
  results.push(r)
  const v = (r && r.verdicts) || []
  const honored = v.filter(x => x.verdict === 'HONORED').length
  log(`[${nn}/${HATS.length}] ${key}: ${v.length} graded, ${honored} HONORED${r && r.pile_file_read === false ? ' (no findings file)' : ''}`)
}

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
