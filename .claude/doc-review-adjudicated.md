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

## Recorded docstring-shape exemptions (settled 2026-08-04, re-raised round 2)

7. **`translation_kernel!` does not carry the verbatim in-place steer sentence.** Deliberate: it
   rebuilds an existing `SeparableKernel` for a new displacement rather than filling a `destination`,
   so the verbatim wording would name an argument its signature does not have. It carries the same
   steer reworded to its own parameter. *(Flagged by three hats in an earlier round, then by hat 06
   again in round 2.)*

8. **`to_physical!`/`to_spectral!` have no standalone in-place steer sentence.** Deliberate: they
   already steer to their allocating siblings for the stronger input-preservation reason (invariant
   11 — the inverse real transform may destroy its input), and the steer is not doubled.

9. **`LalescuSpline` / `LagrangeSpline` document their `T = Float64` keyword in running prose rather
   than a bulleted `The arguments are:` list.** A recorded exemption: a *single element-type keyword*
   bound in one prose clause is not the long-argument-list problem the bulleted-form rule addresses.
   The same exemption covers the callable field's `scheme`. Do not re-raise these two as violations
   of the keyword-triggers-bullets rule.

10. **`Grid3D` uses `The fields are` while `NUFFT` uses `The arguments are:`.** Both are correct and
   the distinction is the rule, not drift: a type that *stores* named, user-readable fields documents
   them under `The fields are`; a constructor taking three or more arguments or any keyword documents
   those under `The arguments are:`.

---

*If you believe an entry here is wrong on the merits, you may say so once, briefly, marked
`confidence: low` — but do not spend a finding slot restating the original complaint.*
