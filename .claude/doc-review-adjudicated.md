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

17. **`FieldTransformPlans` documents its arguments before its fields, where the field types do the
   reverse.** Deliberate: a reader meets a plans object through its constructor — the two witness
   fields it is built from — while a field type's storage is what the reader meets first. Each
   docstring leads with its own primary interface.
