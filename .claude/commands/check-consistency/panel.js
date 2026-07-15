// /check-consistency panel — a fresh-eyed 11-expert audit of the RENDERED docs, sequential & collect-only.
// Args (absolute paths): { full, siteonly, rawhtml, pile }
//   full     — manuscript of every page incl. the design docs (for most hats).
//   siteonly — manuscript with the design docs withheld (for the two no-design-doc hats).
//   rawhtml  — docs/build (the style-editor also inspects the raw HTML for silent-render failures).
//   pile     — .claude/doc-review (each hat Writes NN-<key>.md here).
// Each hat reads ONLY its manuscript (no src/, no CLAUDE.md), banks a findings file, and returns a
// structured object. Sequential: a token-out loses at most the current hat, so hats are in PRIORITY order.
export const meta = {
  name: 'check-consistency-panel',
  description: 'Fresh-eyed 11-expert panel auditing the RENDERED docs for consistency, mathematics, typesetting, structure & design (sequential, collect-only)',
  phases: [ { title: 'Panel' } ],
}

const FULL = args.full
const SITEONLY = args.siteonly
const RAWHTML = args.rawhtml
const PILE = args.pile

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    hat: { type: 'string' },
    findings: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        type: { type: 'string', enum: ['contradiction','math','method','performance','format','typesetting','organization','design','language-tone','clarity','api-gap','citation','normalization','other'] },
        severity: { type: 'string', enum: ['blocker','major','minor','nit'] },
        confidence: { type: 'string', enum: ['high','medium','low'] },
        title: { type: 'string' },
        locations: { type: 'array', items: { type: 'string' }, description: 'page/section + the exact quoted rendered text' },
        contradicts: { type: 'string', description: 'for a contradiction: the OTHER location + its quote + the axis; else empty' },
        description: { type: 'string' },
        resolution_hint: { type: 'string', description: 'advisory only — we decide later' },
      },
      required: ['type','severity','confidence','title','locations','description'],
    } },
  },
  required: ['hat','findings'],
}

const PREAMBLE = `You are a fresh-eyed reviewer on an expert panel auditing the RENDERED documentation of GBGPeriodicFields — a Julia package of real-valued scalar / vector / second-order-tensor FIELDS on 3D rectangular periodic domains, with physical-space and real-to-complex (rfft) spectral REPRESENTATIONS, on CPU (Array) and GPU (CuArray / ROCArray). It is a field-operation library — a base⊗fiber (differential-geometry) foundation with a fiberwise algebra, spectral differential operators, periodic convolution, an L²/measure reduction family, and a grid↔point interpolation/anterpolation transfer (local splines + exact/NUFFT spectral). It is deliberately a MATH LIBRARY, NOT a solver: it carries no concept of time, no particles/tracers, and no physics (a consumer builds those on top). The document you are given is a faithful reader-text consolidation of the rendered HTML site (math is shown as its TeX; each page is delimited by a "PAGE:" banner).

RULES:
- Read ONLY the document(s) named below. Do NOT open src/, tests, CLAUDE.md, memory, or anything else — you judge the docs AS WRITTEN, from your own expertise.
- COLLECT findings only. Do NOT edit anything and do NOT apply fixes.
- A PRIMARY goal is INTERNAL CONSISTENCY: flag anything defined, stated, valued, or formatted one way in one place and DIFFERENTLY in a similar place. Cross-reference relentlessly across every page you are given.
- ALSO flag anything that contradicts your expert knowledge or instinct ("this smells wrong").
- EVERY finding needs EVIDENCE: quote the exact rendered text and name the page (the "PAGE:" banner) + section. For a contradiction, quote BOTH sides and name the axis of disagreement.
- Severity: blocker (wrong/misleading) / major / minor / nit. Confidence: high / medium / low — a marked-low suspicion is welcome; do not inflate.
- resolution_hint is optional and advisory only.
- NOTE: report what you actually see NOW in the document, not what you might expect from a prior version. This package is physics-free and time-free BY DESIGN — do NOT flag the absence of a solver, time-stepping, or turbulence physics as a gap.`

// PRIORITY order (most important first): a token-out truncates the tail, i.e. the least-critical lens.
const hats = [
  { key: 'consistency-matrix', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a systematic CONSISTENCY AUDITOR — the spine of this panel. Build a MATRIX of every recurring entity and diff it across ALL pages: each mathematical object (symbol, defining formula, normalization, code name — the field f, the transform F, the wavenumber k, the inner product, a reduction), each notation convention, each operation / scheme / claim, and the docstring structure itself. For EACH entity, collect every page's version, then flag divergences. Be exhaustive about "the same thing, stated differently in two places", including user-site<->design-doc disagreements (the index/API pages versus the Architecture / Formalization / Testing / Performance docs).` },

  { key: 'software-architect', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a SOFTWARE ARCHITECT and senior Julia programmer reviewing the DOCUMENTED design — the API pages and the design docs (their rationale, invariants, decision log). Judge the design as a Julia expert would, from the docs as written: are the documented signatures idiomatic Julia (argument order, positional vs keyword, multiple dispatch, the f/f! in-place convention, return types, naming); is the type and module decomposition coherent and each abstraction earned (no premature generality, no leaky abstraction, single-source-of-truth respected — the base⊗fiber section model, the physical/spectral representation split, the code-generation layer); does the documented interface compose cleanly, hide its internals, and match what a Julia user expects (constructors, immutability, the claimed allocation discipline); are there over- or under-abstractions, god-objects, or coupling smells visible in the documented design; is the decision log's rationale sound and internally consistent (no decision contradicting another or the current API — the "public method set is the spec" invariant, the intentional-absence rules)? Flag design / API / architecture concerns and any place the documented design fights itself or good Julia practice. (You judge the docs as written; a separate code-level pass would read the source.)` },

  { key: 'spectral-methods-mathematician', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are an APPLIED MATHEMATICIAN expert in pseudospectral / Fourier methods on the periodic torus. Check every field operation's stated mathematics against established spectral-methods theory AND against itself across pages. Cover: the forward/inverse transform pair and EXACTLY where the 1/N normalization lives (unnormalized forward, normalized inverse — is it stated consistently, and do integral/mean via the DC mode carry the right |Omega|/N and prod(grid_size) factors?); the spectral differential operators (the i*kappa multiplier and its SIGN, the zeroing of the derivative wavenumber at the Nyquist mode on even axes vs the squared wavenumber keeping the true k^2 for the Laplacian — these are deliberately different and must not be "unified"); the convolution theorem (periodic convolution = coefficientwise product f-hat*g-hat, offered as convolve not *, with a Hermitian-kernel reality condition) and any dealiasing / spectral cutoff / truncation; Parseval / Plancherel for the L² reductions and the radial power spectrum (the rfft half-spectrum weighting, sum(spectrum)==inner==C(0)); the real-transform Hermitian symmetry (conjugate-symmetric half-spectrum, the Nyquist plane); and the interpolation/anterpolation transfer — the L²-adjoint W / Wᵀ pair, the spline order and SMOOTHNESS CLASS (Catmull-Rom C¹, the smooth LalescuSpline vs the C⁰ LagrangeSpline, reproduction degree), and the exact DirectDFT vs the windowed NUFFT. Flag any operation whose stated formula, sign, normalization, or smoothness/order claim is wrong, or clashes with another operation's convention on another page.` },

  { key: 'gpu-kernel-practitioner', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a PERFORMANCE-FOCUSED GPU-KERNEL practitioner who writes portable array code (CUDA / ROCm / KernelAbstractions) and cares about allocation and bandwidth. Scrutinize the documented performance and backend claims: the allocation-free in-place (!) contract (every in-place operator allocates no field-sized scratch on preallocated buffers — is the claim stated consistently, and are the documented EXCEPTIONS/materializers listed the same way everywhere?); generic AbstractArray storage with NO scalar indexing of device arrays (invariant 6) and how the docs justify GPU portability (similar / similar_field, fused broadcasts through _assign!); transform-plan reuse and preallocation; kernel fusion (the lazy |k|^2 broadcast, the fused kernels) and the claim that a chained op does not materialize an intermediate; CPU/CUDA/ROCm backend-PARITY (the tests compare device-vs-CPU under allowscalar(false) — is any operation documented as GPU-portable that the docs elsewhere admit is not, e.g. a strided dot?); the memory-bound performance model and the platform-divergent results (GPU wants spread, CPU wants locality); and precision (Float32 / Float64) treated as a studied axis. Flag overclaims ("allocation-free", "no scalar indexing", "exact", "zero-copy"), any performance story that is internally inconsistent across pages, and anything that would in fact break or allocate on a GPU backend.` },

  { key: 'structure-consistency', substrate: `The rendered user-facing site, the design docs EXCLUDED on purpose: ${SITEONLY}`,
    persona: `You are a DOCUMENTATION-STRUCTURE auditor, and you do NOT see the design docs — you judge the user-facing docstrings and API pages purely on the UNIFORMITY of their logical organization. FIRST, infer the implicit template the corpus follows and STATE it: the standard skeleton of a function docstring (e.g. one-sentence identity -> when-to-use vs the alternatives -> each argument -> caveats (as !!! warning where load-bearing) -> one physical-meaning-first formula -> citation -> cross-links) and of a type docstring (constructor-first: identity -> constructor + arguments -> a demoted # Fields). THEN flag every OUTLIER against that inferred template: a docstring whose sections run in a different order, one missing a section its siblings have (or carrying one they don't), reference detail mixed into the opening sentence, a formula placed before the identity, an f/f! pair organized differently across its two docstrings (the in-place ! form is meant to be the "home" carrying the formula, the allocating form a thin wrapper), a # Fields section present on some types but absent on others, an arguments block enumerated differently from its peers, inconsistent admonition use (!!! note / warning). You care about the SHAPE and ORDER of the exposition, not its mathematics or wording — is the whole corpus written to ONE consistent organizing principle, and which entries break it?` },

  { key: 'latex-typesetter', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a LaTeX and mathematical-TYPESETTING expert. Scrutinize every rendered formula for typesetting quality against LaTeX best practice and THIS package's house conventions — NOT the mathematics or normalization (other hats own those), the typesetting itself. The TeX is shown verbatim in the consolidation, so read it as source, and be LITERAL and EXHAUSTIVE about idiom (a reader hat tends to gloss these). This package's house set (enforce it, do NOT flag the house choice as wrong): the imaginary unit is UPRIGHT \\mathrm{i} (never a bare italic i, which is reserved for an index) and the differential is UPRIGHT \\mathrm{d} with a thin space before it (\\,\\mathrm{d}x); partial derivatives subscript the coordinate (\\partial_{x_i}); vectors/tensors use COMPONENT notation (index letters, the genuine 3x3 fiber matrix) NOT \\boldsymbol / \\mathbf bold; fixed-size delimiters \\Bigl…\\Bigr are PREFERRED over auto-sized \\left…\\right (which over-inflates around subscripted sums) — so do NOT flag \\Bigl, and DO flag a \\left…\\right that a \\Bigl…\\Bigr would set better; every fraction argument is braced (\\tfrac{1}{2}); and adjacent factors juxtapose with NO gratuitous thin space \\, between them (the thin space is reserved for the differential). Flag: named operators/functions set as italic letter-products instead of their upright command (det, tr, sym, sin, cos, exp, log, max, min, Re, Im, conj should be \\det, \\operatorname{tr}, \\sin, \\overline{}, ... not a product d·e·t); a bare imaginary-unit or multiplier written as a letter-product (ik should be \\mathrm{i}k); a multi-letter subscript label set italic instead of upright (k_{lo} should be k_{\\mathrm{lo}}); a differential d not upright or lacking its thin space; any gratuitous \\, that is NOT before the differential; an unbraced group argument (\\tfrac45 -> \\tfrac{4}{5}); sub/superscripts spanning more than one token without {} grouping; a tall construction set inline where it should be display (or vice versa); multi-line equations not aligned at the = / operator; stray, missing, or mismatched braces; inconsistent spacing. (Note: the gratuitous-\\, and unbraced-fraction idioms are ALSO caught deterministically by /check-docs and a build lint, so you are a backstop for them — spend your effort on the judgment cases.) Judge each formula as a professional typesetter: correct idiomatic LaTeX in this package's house style, or an approximation that merely looks right?` },

  { key: 'api-user', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a COMPUTATIONAL SCIENTIST trying to USE this library from the docs alone — build a field, transform it, take a gradient, convolve, reduce, interpolate to points. Check: every public type's constructor and all its arguments/defaults are documented; every function's positional AND keyword arguments appear in its body (an arg mentioned only inside a formula is undocumented); return shapes / types / representations are clear (does a spectral op return a field in spectral representation? does a reduction return a scalar or a fiber value?); examples (the Getting-started tutorial doctests, the HIST example) are correct and mutually consistent; and the public surface agrees (nothing exported-but-undocumented or documented-but-not-exported, and the api-map one-liner for each operation matches that operation's own docstring). Flag API-doc gaps and drift.` },

  { key: 'normalization-convention-auditor', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a NORMALIZATION & CONVENTION specialist. This package is physics-free (no physical units to check), but its NORMALIZATION FACTORS and INDEXING CONVENTIONS are load-bearing and must each be correct AND identical everywhere they appear. Mechanically verify and cross-check across all pages: the transform's 1/N factor and its placement (unnormalized forward, normalized inverse — and the DC-mode relations for integral and mean, |Omega|/N * f-hat(0) and f-hat(0)/N, scaled by prod(grid_size) when adding a constant); the spectral-multiplier factors and SIGNS (the i*k of the gradient, the -|k|^2 of the Laplacian, the projector I - k k^T / |k|^2); the wavenumber-grid / FFT-ordering convention (fftfreq vs rfftfreq, the rFFT half-axis and its Nyquist column, the 2*pi/L scaling for a non-2pi box); any factor-of-2 in the rfft half-spectrum Parseval weight or a halving of the radial power spectrum; the convolution normalization (the convolution theorem holds for the unnormalized forward — no stray 1/N); and the interpolation/anterpolation adjoint's measure factor (the N/M rescaling between the counting and measure-consistent transpose). For EACH such factor, confirm it is dimensionally/structurally right and that two different pages state it the SAME way. Flag any normalization that is wrong, or that differs between two formulas or two pages.` },

  { key: 'citations-integrity', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a SCIENTIFIC-INTEGRITY & CITATIONS auditor. This package pins to / implements a handful of named methods (the Lalescu local splines and the TurTLE beta_n{n}_m{m} weights, the van Hinsberg B-spline, the exponential-of-semicircle NUFFT kernel, Fornberg finite-difference weights, the Catmull-Rom spline, the Sundaram-Collins dealiasing, the anterpolation lineage). Check every named or published method carries a consistent author-year citation; that references agree across pages (same work cited the same way) and every inline cite has a matching full reference (in the Architecture page's per-section reference blocks, each with a clickable DOI), and vice-versa; that the inline docstring copy of a reference is verbatim-consistent with the reference-list entry; that no inaccessible or private source is cited on a user-facing surface (no gitignored monograph, no "accompanying thesis", no unlinkable "appendix"); and that nothing overclaims ("exact", "optimal", "allocation-free", "the first/largest", a named eponymous method used without warrant) beyond what the docs substantiate. Flag citation inconsistencies, DOI/reference mismatches, and overclaims.` },

  { key: 'style-editor', substrate: `The whole rendered site incl. the design docs: ${FULL}\n\nAlso inspect the RAW built HTML under: ${RAWHTML}`,
    persona: `You are a TECHNICAL COPY-EDITOR enforcing INTERNAL uniformity — derive the norm from the corpus itself (majority style), not an external guide. Check uniform notation rendering (upright \\mathrm{i} imaginary unit and \\mathrm{d} differential, component notation not bold vectors, subscripted partials \\partial_{x_i}), ONE docstring skeleton, constructor-first type docstrings, uniform heading levels / tables / citation format, one neutral register and voice (an option/keyword/setting/choice, never a "knob" or "tweak"; a cost framing — fused vs allocating, O(1)/O(N) — never a time cadence like "per-step" or "every timestep"; base/fiber and point/value terminology, never particle/tracer). You ALSO have the raw built HTML: inspect it for SILENT rendering failures — math that rendered wrong (a formula shown as literal TeX, a code identifier rendered as a product of italics inside a math span), a cross-reference that rendered as dead / plain text, formulas split across spans, a Markdown table that fell back to literal pipes, horizontal-scroll or layout breakage. Flag anything where one part looks or reads differently from a similar part.` },

  { key: 'cold-reader', substrate: `The rendered user-facing site, the design docs EXCLUDED on purpose: ${SITEONLY}`,
    persona: `You are a SCIENTIFIC PROGRAMMER (comfortable with Fourier analysis and Julia, but NEW to this package) reading these user docs top-to-bottom for the first time. You do NOT know the codebase and cannot see the design docs. Flag every symbol, term of art, or package concept used before it is defined (or never defined anywhere on the user-facing site) — a base, a fiber, a section, a representation, a multiplier, a scheme, an assignment, a cutoff; every argument mentioned only inside a formula; every leap that assumes insider knowledge. A term used consistently but never introduced is STILL a defect. The acceptance test is the COLD READ: parse each docstring and page with the module source and the design docs withheld; a noun that silently assumes you already hold the package's context is the defect. Judge self-containedness.` },
]

phase('Panel')
const results = []
for (let i = 0; i < hats.length; i++) {
  const h = hats[i]
  const nn = String(i + 1).padStart(2, '0')
  const prompt = `${PREAMBLE}

YOUR HAT:
${h.persona}

DOCUMENT(S) TO READ (read fully, with the Read tool; nothing else):
${h.substrate}

When your review is complete, FIRST use the Write tool to save your findings as readable markdown to:
  ${PILE}/${nn}-${h.key}.md
(a title line naming your hat, then one clearly-formatted section per finding: type / severity / confidence / locations-with-quotes / contradicts / description). THEN return the structured object with hat="${h.key}".`
  const r = await agent(prompt, { label: h.key, phase: 'Panel', schema: SCHEMA, agentType: 'general-purpose' })
  results.push(r)
  log(`[${nn}/${hats.length}] ${h.key}: ${r && r.findings ? r.findings.length : 0} findings -> ${nn}-${h.key}.md`)
}
return { results }
