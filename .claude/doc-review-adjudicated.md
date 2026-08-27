# Adjudicated — do NOT re-flag

Findings previously raised by this panel and **settled as not-a-defect**. A blind hat cannot know
these were adjudicated, so it re-litigates them every round; this file is injected into every hat's
preamble to stop that.

**Scope rule — this list holds ONLY findings settled as NOT defects.** A finding that was *fixed*
never goes here: a fix can itself be wrong, and re-flagging it is exactly how the panel earns its
keep. (Round 2 caught a mathematically false sentence that round 1's fix pass had *introduced* — had
"fixed" items been suppressed, that error would have shipped.) Two admissible classes:

- **Extraction artifacts** — the finding is about the manuscript pipeline, not the site.
- **User-closed design decisions** — the inconsistency is real and intentional.

---

## Extraction artifacts (the rendered site is fine; the reader-text consolidation drops it)

1. **"No reference carries a clickable DOI / link."** False. The manuscript consolidation strips
   `[text](url)` to its text, so every DOI vanishes from what you are reading. The built HTML carries
   them — 13 in `ARCHITECTURE` alone. Do not flag missing DOIs, missing links, or missing URLs
   anywhere in the corpus. *(Raised round 1 by hats 10+11; round 2 again by hat 10 as its top finding,
   while hat 11 independently caught the artifact.)*

2. **Block boundaries appear to collapse — a `# References` heading running into the previous bullet,
   or an admonition title concatenated onto its body's first word (`...allocates nothing**This**
   operation applies...`).** The consolidation flattens block structure, so headings, admonition
   headers and their bodies lose their separation. Verified in the built HTML: an admonition renders
   its title in `<header class="admonition-header">` and its body in a separate `<div
   class="admonition-body">`. **Never report spacing, run-on text, or block separation from this
   manuscript** — judge only the *content* of a block. (Raised by hats 06 and 08 in round 2.)

3. **Unicode math in a comment of the Literate example (`examples/HIST_CPU.jl`), reported as
   rendering in prose.** Check the marker before flagging: a `##` double-hash comment stays a **code**
   comment on the built page (Literate's documented escape hatch for notes that must not render), and
   only a full-line single-`# ` comment becomes prose. The manuscript flattens both into the same
   text, so they cannot be told apart there. The one instance raised in round 2 — the `S⁽ᴱ⁾(r)`
   snapshot block — was verified to sit inside a `<code>` element in the built HTML. Unicode math is
   correct there and must NOT be converted to LaTeX.

4. **A `docs/ARCHITECTURE.md` §13 decision entry "never states its own decision number".** Extraction
   artifact. §13 is an ordered list, so each entry's number is its `<ol>` marker — present in the
   source (`62. **Any kernel class may weight…**`) and rendered by the browser, but stripped when the
   HTML is flattened to this manuscript. Never infer a numbering gap from this text. *(Raised by hat 01
   in round 3, twice.)*

## User-closed design decisions (real, intentional, settled 2026-08-05)

5. **`radial_kernel(sigma, reference, multipliers)` leads with its function where the other kernel
   builders lead with `reference`.** Intentional and closed by the user. Do not re-raise the argument
   order of the kernel-builder family.

6. **`scheme` is a positional-with-default argument on `interpolate`/`anterpolate` and a keyword on
   the callable sugar `field(x; scheme = …)`.** Intentional and closed by the user. Do not re-raise
   the calling convention of `scheme`.

7. **`weighted_inner` accepts a complex `StoredKernel` weight and uses its real part instead of
   throwing, where the other three classes throw.** Intentional and closed by the user (2026-08-05).
   The asymmetry is real and is documented in a `!!! warning`; it is not a defect to fix. Reaching that
   path takes a deliberate act — hand-building a stored kernel's coefficients, or explicitly
   materializing a complex one — and a consumer who does either knows what they are doing. The only
   honest alternative is an ``O(N)`` scan of the coefficients on every call, which the reduction's
   single-pass contract does not permit and which is not worth paying to protect a deliberate act. Do
   not re-raise the inconsistency, and do not propose the scan.

## Recorded docstring-shape exemptions (settled 2026-08-04, re-raised round 2)

8. **`translation_kernel!` does not carry the verbatim in-place steer sentence.** Deliberate: it
   rebuilds an existing `SeparableKernel` for a new displacement rather than filling a `destination`,
   so the verbatim wording would name an argument its signature does not have. It carries the same
   steer reworded to its own parameter. *(Flagged by three hats in an earlier round, then by hat 06
   again in round 2.)*

9. **`to_physical!`/`to_spectral!` have no standalone in-place steer sentence.** Deliberate: they
   already steer to their allocating siblings for the stronger input-preservation reason (invariant
   11 — the inverse real transform may destroy its input), and the steer is not doubled.

10. **`LalescuSpline` / `LagrangeSpline` document their `T = Float64` keyword in running prose rather
   than a bulleted `The arguments are:` list.** A recorded exemption: a *single element-type keyword*
   bound in one prose clause is not the long-argument-list problem the bulleted-form rule addresses.
   The same exemption covers the callable field's `scheme`. Do not re-raise these two as violations
   of the keyword-triggers-bullets rule.

11. **`Grid3D` uses `The fields are` while `NUFFT` uses `The arguments are:`.** Both are correct and
   the distinction is the rule, not drift: a type that *stores* named, user-readable fields documents
   them under `The fields are`; a constructor taking three or more arguments or any keyword documents
   those under `The arguments are:`.

---

*If you believe an entry here is wrong on the merits, you may say so once, briefly, marked
`confidence: low` — but do not spend a finding slot restating the original complaint.*

## Verified-not-defects added after round 6 (2026-08-15)

12. **`\lvert…\rvert` "leaking" outside Markdown tables.** The glossary row states an
   *equivalence* — the bar spellings "are the same symbol, and both denote one concept" — not a
   ban on `\lvert` outside tables. The table needs the escape because a literal pipe is eaten as
   a GFM column delimiter; that is the row's explanation, not a scoping rule. Raised as major in
   round 5 (dismissed) and again in round 6 by the same hat, because round 5's dismissal was never
   written here. Do not re-raise, and do not churn hundreds of formulas to normalize the spelling.

13. **`translation_kernel!` "inverts" the f/f! formula home** (the allocating form carries the
   formula, the `!` form points back). Deliberate, and the same reasoning as item 8: the `!` form
   rebuilds an existing `SeparableKernel` for a new displacement rather than filling a
   `destination`, so the builder is where the operation's meaning lives. Item 8 settled the steer
   sentence; this settles formula ownership, which round 6 correctly noted item 8 did not cover.

14. **The three `\begin{CD}` commutative diagrams may fail silently in KaTeX.** Checked 2026-08-15:
   the site loads KaTeX 0.16.8, which has supported the amscd `CD` environment since 0.11.0, and
   this Documenter build renders math **client-side** — there are zero server-side `katex` spans,
   so raw TeX inside `<p class="math-container">` is the normal shape of every formula on the site
   and is not evidence of a rendering failure. Do not infer a KaTeX failure from raw TeX in the
   built HTML.

15. **The validity clause sits before the in-place steer in some `!` docstrings and after it in
   others** (`tr!`/`sym!`/`skew!`/`dev!` vs `det!`/`transpose!`/`norm!`). Read all seven together and
   the split tracks content, not drift: a **one-clause** validity statement ("linear and
   representation-preserving, so it is defined for both") is part of the identity sentence and rides
   with it, while a **multi-sentence** validity paragraph — one that also carries the aliasing
   consequence, or contrasts with Julia's own `transpose` — is its own paragraph and follows the
   steer. Both satisfy the rubric, which fixes the steer only relative to the identity paragraph and
   the arguments. Do not normalize.

16. **Admonitions sit in three different positions across docstrings.** Deliberate: the position
   tracks what the caveat qualifies. An operation-wide caveat follows the identity (`helmholtz_projection!`'s
   nonlocality), an argument-specific one follows the argument list (`exponential_convolve!`'s offset
   hypothesis), and one that qualifies a formula follows the formula (`translation_kernel`'s Nyquist
   attenuation). The rubric mandates a custom title, not a slot.

18. **`similar_field` / `similar_pointvalues` should extend `Base.similar`.** Raised round 6,
   **user-closed 2026-08-15** (decision 67). Declined on four grounds, and the reasoning is now on both
   docstrings: `Base.similar`'s second positional argument means an element type or dimensions where
   this one means tensor order; `similar(u, Float32)` would read as the implicit precision change
   invariant 14 and decision 63 exist to refuse; the `data` form wraps supplied storage, which
   `Base.similar` never does; and a section is not an `AbstractArray`. Defining only the
   no-extra-argument `Base.similar(::AbstractFiberSection)` was considered and declined with it, as a
   second spelling of one operation. Do not re-raise.

17. **`FieldTransformPlans` documents its arguments before its fields, where the field types do the
   reverse.** Deliberate: a reader meets a plans object through its constructor — the two witness
   fields it is built from — while a field type's storage is what the reader meets first. Each
   docstring leads with its own primary interface.

## /check-docs 2026-08-27 — three dismissals, recorded so they are auditable

**A dismissal must quote the banked finding's title verbatim.** `lint_review_closure()` in
`docs/make.jl` matches a finding to its dismissal by title, so a paraphrase closes nothing and the
round stays open — which is the correct failure, since a dismissal nobody can match to a finding is
not a record of anything.


These were dismissed during the fix pass and the reasons lived only in a commit message, where no
verifier could see them. `verify-fixes.js` correctly graded all three **UNDONE**, because a dismissal
that is not recorded in the tree is indistinguishable from neglect. They are recorded here now; a
future round that re-raises one should close against this note or overturn it explicitly.

- **No FORMALIZATION/TESTING mention of decisions 74 and 75** — the banked finding's exact title, quoted so a gate can match it. Decision 74 is an allocation-shape change and
  decision 75 is I/O persistence; neither states a new mathematical fact. Their siblings carry no
  entries either — `similar_field` has none, and `write_field`/`read_field` have none — so adding
  these two would make the page inconsistent in the other direction. **Overturn this** if a later
  round shows an untested nontrivial claim resting on either.
- **Formula-like pseudo-code in backticks in the FiberSections codegen builders** — quoted verbatim from the banked finding. The spans
  (`destination = α * formula + β * destination`) describe the *shape of the code the generator
  emits*, not mathematics, in internal `_`-prefixed builders that the rubric already treats loosely.
  Rewriting them as LaTeX would misrepresent them as formulas.
- **The examples' advect! hand-rolls point motion instead of using displace!/wrap!** — quoted verbatim from the banked finding. `displace!` covers the displacement, but the
  demo's RK2 midpoint update is *time-stepping*, which is a consumer concern the package deliberately
  excludes (invariant 12). CLAUDE.md already queues that rewrite for the consumer package. **Overturn
  this** if the demo is rewritten for other reasons, since it would then be free to adopt the verb.

## /check-docs 2026-08-27 — five closed by verification, not by dismissal

These five were fixed. They are recorded here because the verifier's mechanical demotion
demoted them anyway: each grader's `class_surfaces` answer named the class by **identifier**
(`radial_kernel`, "the same three builders") rather than by file path or line, and the predicate
demands a named file or an explicit absence claim. The fix is real, the citation was thin, and
the honest close is a checkable record rather than a fourth loosening of the predicate — three
successive rounds have already been spent tuning it, which is itself the argument for IT's
choice of testing **emptiness** rather than parsing content.

Each was verified against the tree, not against the grader's account:

- **radial_kernel uses the bulleted argument form with two positional args and no keyword** —
  fixed. The only `The arguments are:` lists remaining in `src/Convolution.jl` are at lines 934,
  1265, 1424 and 1648, belonging to `convolve`, `convolve!`, `spectral_band` and
  `translation_kernel!`; every one takes three or more arguments, which the rubric's shape rule 1
  requires to be bulleted. No two-argument builder carries one.
- **spectral_cutoff uses the bulleted argument form with two positional args** — fixed, same
  evidence.
- **translation_kernel uses the bulleted argument form with two positional args** — fixed, same
  evidence.
- **'deck group' is used once and never glossed** — fixed. `docs/FORMALIZATION.md:781` now reads
  "deck group — the whole-period lattice shifts that map the unwrapped picture onto itself".
- **'the whole hierarchy' has no clear antecedent** — fixed. The phrase no longer occurs anywhere
  in `src/` or the four rationale docs; the passage was rewritten rather than patched.

Overturn condition: if a grep finds a two-argument, no-keyword builder still carrying a bulleted
argument list, or either term used cold again, reopen the finding rather than citing this note.
