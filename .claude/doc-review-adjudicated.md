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

## User-closed design decisions (real, intentional, settled 2026-08-05)

2. **`radial_kernel(sigma, reference, multipliers)` leads with its function where the other kernel
   builders lead with `reference`.** Intentional and closed by the user. Do not re-raise the argument
   order of the kernel-builder family.

3. **`scheme` is a positional-with-default argument on `interpolate`/`anterpolate` and a keyword on
   the callable sugar `field(x; scheme = …)`.** Intentional and closed by the user. Do not re-raise
   the calling convention of `scheme`.

---

*If you believe an entry here is wrong on the merits, you may say so once, briefly, marked
`confidence: low` — but do not spend a finding slot restating the original complaint.*
