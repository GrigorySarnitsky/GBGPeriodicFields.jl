# /check-consistency — 12-hat panel, 2026-08-04

**85 findings across 12 hats. All closed: 79 fixed, 6 dismissed or confirmed false positives.**

Run after three `/check-docs` rounds (~90 → 40 → 21) had declared the corpus clean. The result settles
the convergence question: **convergence is per-LENS, not global.** A new lens on the same documentation
returned a round-1-sized pile.

## Dispositions

| hat | findings | fixed | dismissed / FP |
|:---|---:|---:|:---|
| 01 consistency-matrix | 3 | 3 | — |
| 02 software-architect | 9 | 7 | 2 escalated (below) |
| 03 spectral-mathematician (anchor) | 12 | 11 | 1 was a verified-clean note |
| 04 differential-geometer (anchor) | 15 | 15 | — |
| 05 gpu-kernel-practitioner | 5 | 5 | — |
| 06 structure-consistency | 10 | 9 | 1 (FieldTransformPlans' two lists — rule 6b requires the split) |
| 07 latex-typesetter | 5 | 3 | 2 (wrapped inline math — build-lint enforces the failure mode; `CD` env — KaTeX supports it, rendered client-side) |
| 08 api-user | 5 | 5 | — |
| 09 normalization-auditor | 2 | 2 | — |
| 10 citations-integrity | 3 | 1 | 2 FALSE POSITIVES (below) |
| 11 style-editor | 6 | 5 | 1 (FiberSections internal section holds no types, so the split rule does not apply) |
| 12 cold-reader | 10 | 10 | — |

## The two mathematics errors

- **The measure-weighted adjoint was derived from the wrong pairing.** `N/M` is the ratio of the two
  *normalized* measures; the sentence named cell-volume against counting, which gives `N/|Ω|`.
- **`_squared_wavenumber_broadcast` advertised the pre-decision-42 Helmholtz projector**, naming an
  operator that no longer consumes it and printing the `|k|²` denominator decision 42 replaced.

## Confirmed false positives — do not re-flag

1. **"No reference carries a DOI"** (hats 10, 11). Artifact of the manuscript extraction dropping
   `[text](url)`; the built HTML has 13 DOI links in ARCHITECTURE alone.
2. **"Catmull–Rom has no inline author-year anchor"** (hat 10). It does: `ARCHITECTURE.md:809`.

## Escalated and CLOSED by the user (2026-08-05) — intentional, do not re-flag

- **02/F3** the callable `field(x; scheme = …)` takes `scheme` as a keyword while every named transfer
  verb takes it positionally. **Left as is by decision.** A keyword suits a one-point convenience call
  whose whole point is that you usually want the default; making it positional would be breaking.
- **02/F5** `radial_kernel(sigma, reference, multipliers)` leads with its function where the named
  builders lead with `reference`. **Left as is by decision.** The symbol is exactly what distinguishes
  this builder from the named ones, so leading with it follows Julia's higher-order convention
  (`map(f, collection)`); reordering would be breaking.

Both were raised as genuine interface inconsistencies rather than laundered as "by design", and both
were then settled by the user on the trade-off. A later panel that re-raises either should be closed
against this entry.

## Recorded exemption

`translation_kernel!`'s in-place steer is reworded rather than verbatim, because it rebuilds a kernel
rather than filling a `destination`. Flagged independently by three hats, now recorded in `CLAUDE.md`
so a fourth does not re-raise it.
