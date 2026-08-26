// /bug-hunt — a CODE instrument. Ported from GBGIsotropicTurbulence 2026-08-27 (mechanism only).
//
// THE GAP IT FILLS. /check-docs and /check-consistency both audit PROSE. Neither asks whether the
// code is correct. A docstring can be flawless about a function that returns the wrong number and
// both instruments pass it clean.
//
// THE ONE DESIGN RULE, from which everything else follows:
//
//     A static claim about code is a hypothesis. The only admissible evidence is a program that FAILS.
//
// This is a correction for a measured failure mode, not a preference. An agent reading code and
// reporting what "looks wrong" produces fluent, confident, unfalsifiable prose. In a documentation
// instrument that costs a wasted read. HERE it costs a fix pass on WORKING CODE — strictly worse than
// the imagined bug, because the tree gets edited, the suite still passes, and afterwards nobody can
// tell whether anything was ever wrong.
//
// So the hunt is static and the confirmation is DYNAMIC. Every candidate reduces to a WITNESS: a
// self-contained @testset asserting the CORRECT behaviour, therefore observed to FAIL on this tree.
//   witness FAILS   -> that IS the finding. Unchanged, it becomes the regression test the fix flips.
//   witness PASSES  -> not a bug. Discarded, however good the argument was.
//   no witness      -> not actionable. Reported as a latent hazard, never fixed.
//
// A SECOND TRAP, and the adjudication phase exists for it: a witness can fail because the WITNESS is
// wrong. A test asserting a false identity fails on correct code. So a failing witness is necessary
// and not sufficient — an independent lane must confirm the witness asserts what the mathematics or
// the documented contract actually requires, from an oracle, before the candidate is a finding.
//
// LANES ARE FREE, NOT CLASS-BOUND. IT measured unconstrained readers beating eight defect-class lanes
// at a third of the cost, and catching four regressions IT had introduced itself. A class list is a
// hypothesis the instrument then reports `complete` over — a false comfort. Lanes here differ by
// TERRITORY (which files) so coverage is spread, never by defect class.
//
// Args (absolute paths): { repo, pile, strength }
//   repo     — the repository root.
//   pile     — a scratch directory for witnesses and lane reports. Promoted witnesses move to
//              test/regressions/ when a fix lands; the pile itself is disposable.
//   strength — 'economy' (default) | 'full'.
export const meta = {
  name: 'bug-hunt',
  description: 'Hunt for real defects in the CODE, admitting only candidates backed by a witness test observed to fail',
  phases: [ { title: 'Hunt' }, { title: 'Adjudicate' } ],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo
const PILE = A.pile
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'
if (!REPO || !PILE) throw new Error('bug-hunt needs { repo, pile }')

// Territories, not defect classes. Each lane reads its own slice of the package and is otherwise
// unconstrained. The split is by module grouping so two lanes rarely read the same file, and the
// mathematical contracts a lane can test against differ genuinely between them.
const LANES = [
  { key: 'fields-transforms', territory: 'src/Fields.jl — the grid, the layouts, the field types, the spectral multipliers, the transform plans, reality_residual, adapt/adapt!. The exact contracts here are the FFT normalization (forward unnormalized, inverse normalized), the zero-Fourier-mode rule for adding a constant, the Nyquist split between derivative and squared wavenumbers, and the transform input-preservation contract.' },
  { key: 'algebra-fibers', territory: 'src/FiberSections.jl and src/FieldAlgebra.jl — the fiber types, the code generators, the fused executor, and the whole M2+M3 algebra including map!/map, det, tr and the alpha/beta accumulation forms. Contracts: the alpha/beta branch on iszero(beta), aliasing safety of every fused pass, and per-component formulas that must match their own docstrings.' },
  { key: 'operators-convolution', territory: 'src/DifferentialOperators.jl and src/Convolution.jl — gradient, divergence, curl, symmetric_gradient, laplacian, inverse_laplacian, helmholtz_projection, and the four kernel storage classes. Contracts: div(curl)=0, curl(grad)=0, the projector being idempotent and divergence-annihilating at every mode, the translation kernel Nyquist split, and every kernel class agreeing bitwise with its materialized form.' },
  { key: 'reductions-measure', territory: 'src/Reductions.jl — the L2/measure family, weighted_inner, the mapped forms, the radial spectrum and correlation, and the statistics. Contracts: Parseval between representations, sum(spectrum)==C(0)==inner, the cell-volume versus counting measure, and Bessel correction in var.' },
  { key: 'points-transfer', territory: 'src/Points.jl and src/Interpolation.jl — the point layer, displace!/wrap!, and the whole grid<->point transfer including both spline families, DirectDFT and NUFFT. Contracts: the L2-weighted adjoint relation M*inner(Wf,q)==N*inner(f,Wtq), partition-of-unity conservation, polynomial reproduction degree, and DirectDFT reproducing a band-limited field exactly.' },
]

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    lane: { type: 'string' },
    candidates: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        title: { type: 'string' },
        location: { type: 'string', description: 'file:line of the suspected defect' },
        claim: { type: 'string', description: 'what the code does versus what it must do, and the ORACLE for "must" — a docstring contract, a mathematical identity, a published definition' },
        witness_path: { type: 'string', description: 'absolute path of the witness file you wrote, or empty if none could be written' },
        observed: { type: 'string', enum: ['FAILS','PASSES','ERRORS','NOT-WRITABLE'], description: 'what actually happened when you RAN it — never what you expect would happen' },
        run_output: { type: 'string', description: 'the decisive lines of the actual julia output, quoted' },
      },
      required: ['title','location','claim','witness_path','observed','run_output'],
    } },
    territory_note: { type: 'string', description: 'what you read and what you deliberately did not reach' },
  },
  required: ['lane','candidates','territory_note'],
}

const HUNT_PREAMBLE = `You are hunting for REAL DEFECTS in the CODE of GBGPeriodicFields, a Julia library of real-valued scalar/vector/tensor fields on 3D periodic domains, with physical and real-to-complex spectral representations, on CPU and GPU.

THE RULE THAT GOVERNS THIS ENTIRE TASK:

    A static claim about code is a hypothesis. The only admissible evidence is a program that FAILS.

You will read code and form suspicions. A suspicion is worth NOTHING here until you have written a
WITNESS and RUN it. A witness is a self-contained Julia @testset that asserts the CORRECT behaviour —
so if the defect is real, running it on this tree FAILS.

PROCEDURE, per candidate:
1. Form the suspicion from reading. Name the ORACLE for what the code SHOULD do: a mathematical
   identity, a documented contract in the docstring, a normalization convention, a published
   definition. "It looks wrong" with no oracle is not a candidate.
2. Write a self-contained witness to ${PILE}/witness-<short-name>.jl. It must \`using GBGPeriodicFields\`,
   construct its own inputs, and assert the CORRECT behaviour. No dependence on other witnesses.
3. RUN IT: \`cd ${REPO} && julia --project ${PILE}/witness-<short-name>.jl\`
4. Record what ACTUALLY happened in \`observed\`, and quote the real output in \`run_output\`.

WHAT EACH OUTCOME MEANS — this is not bookkeeping, it decides whether you report the candidate at all:
- FAILS  -> a genuine candidate. Report it. The witness is the finding.
- PASSES -> NOT A BUG. Discard it however convincing your reasoning was. Do not report it. Do not
            "explain" why it should still be a concern. The program disagreed with you and it wins.
- ERRORS -> your witness is broken (a MethodError, a typo, a wrong constructor). Fix the witness and
            re-run. An erroring witness is evidence about you, not about the package.
- NOT-WRITABLE -> you cannot construct an oracle or cannot express the assertion. Report it as a
            latent hazard with witness_path empty. It will NOT be fixed on this evidence, and that is
            correct.

HARD RULES:
- NEVER report a candidate whose witness passes. The instrument's value is entirely in this refusal.
- NEVER edit any file under src/, test/ or docs/. You write witnesses into the pile and nothing else.
- Prefer FEW, SHARP, RUN candidates over many speculative ones. Three failing witnesses are worth more
  than twenty paragraphs of suspicion.
- The package is deliberately a math library with NO time, NO particles and NO physics. The absence of
  a solver is not a defect. Deliberate absences (no field*field multiply in spectral representation,
  no tensor order above 2) are documented design, not bugs — check the docstring before flagging one.
- A defect the test suite ALREADY catches is not a finding: if \`Pkg.test()\` would fail on it, it is
  not latent. Your witnesses target what the suite passes over.`

phase('Hunt')
const laneResults = []
for (const lane of LANES) {
  const prompt = `${HUNT_PREAMBLE}

YOUR TERRITORY (read this; you may read anything else in the repo to understand it, but hunt HERE):
${lane.territory}

Repository root: ${REPO}
Witness pile:    ${PILE}

Write your lane report as markdown to ${PILE}/hunt-${lane.key}.md (one section per candidate: title,
location, oracle, witness path, observed outcome, quoted output), THEN return the structured object
with lane="${lane.key}".`
  const r = await agent(prompt, { label: `hunt:${lane.key}`, phase: 'Hunt', schema: SCHEMA,
                                  agentType: 'general-purpose', ...(STRENGTH === 'economy' ? { model: 'sonnet' } : {}) })
  laneResults.push(r)
  const c = (r && r.candidates) || []
  log(`hunt:${lane.key} — ${c.length} candidates (${c.filter(x => x.observed === 'FAILS').length} with a FAILING witness)`)
}

// Only candidates with a witness OBSERVED TO FAIL reach adjudication. Everything else is already
// decided by the rule: a passing witness is not a bug, an erroring witness is not evidence, and a
// hazard with no witness is reported but not actioned.
const failing = laneResults.flatMap(r => ((r && r.candidates) || []).filter(c => c.observed === 'FAILS'))
const hazards = laneResults.flatMap(r => ((r && r.candidates) || []).filter(c => c.observed === 'NOT-WRITABLE'))
log(`${failing.length} candidates carry a failing witness; ${hazards.length} latent hazards with no witness`)

const ADJUDICATION_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    title: { type: 'string' },
    reproduced: { type: 'boolean', description: 'did the witness fail when YOU ran it' },
    witness_is_correct: { type: 'boolean', description: 'does the witness assert what the mathematics or documented contract actually requires' },
    verdict: { type: 'string', enum: ['CONFIRMED','WITNESS-WRONG','NOT-REPRODUCED','ALREADY-COVERED'] },
    reasoning: { type: 'string', description: 'the oracle, expanded — show the identity or quote the contract' },
    run_output: { type: 'string' },
  },
  required: ['title','reproduced','witness_is_correct','verdict','reasoning','run_output'],
}

phase('Adjudicate')
const adjudicated = await parallel(failing.map(c => () => agent(
  `A hunt lane claims a defect in GBGPeriodicFields and backs it with a witness test observed to FAIL.

Your job is ADVERSARIAL and has two parts, and the second is the one that matters:

1. REPRODUCE: run the witness yourself — \`cd ${REPO} && julia --project ${c.witness_path}\` — and record
   whether it actually fails.

2. DECIDE WHETHER THE WITNESS IS RIGHT. A witness can fail because the WITNESS is wrong: a test
   asserting a false identity fails on perfectly correct code, and adopting it would send a fix pass
   at working code. So derive the correct behaviour INDEPENDENTLY, from an oracle — expand the
   mathematical identity, or quote the documented contract from the docstring — and check that what
   the witness asserts is what that oracle requires. Default to WITNESS-WRONG if you cannot derive it.

Also check ALREADY-COVERED: if the existing suite would catch this (grep test/ for an equivalent
assertion), it is not a latent defect.

CANDIDATE
  title:    ${c.title}
  location: ${c.location}
  claim:    ${c.claim}
  witness:  ${c.witness_path}
  lane's observed output: ${c.run_output}`,
  { label: `adjudicate:${c.title}`.slice(0, 60), phase: 'Adjudicate', schema: ADJUDICATION_SCHEMA,
    agentType: 'general-purpose' })))

const confirmed = adjudicated.filter(Boolean).filter(a => a.verdict === 'CONFIRMED')
log(`ADJUDICATED: ${confirmed.length} CONFIRMED of ${failing.length} candidates with failing witnesses`)
for (const a of adjudicated.filter(Boolean)) if (a.verdict !== 'CONFIRMED') log(`  dismissed (${a.verdict}): ${a.title}`)

// A confirmed finding arrives WITH its regression test already written and already failing. Promote
// the witness into test/regressions/ UNCHANGED — the fix must flip it, and a witness edited to suit
// the fix has stopped being evidence.
return { confirmed, dismissed: adjudicated.filter(Boolean).filter(a => a.verdict !== 'CONFIRMED'), hazards }
