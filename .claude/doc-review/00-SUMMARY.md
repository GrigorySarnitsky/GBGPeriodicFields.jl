# /check-consistency — panel round 2, 2026-08-05

**87 findings, against round 1's 85 — but see the CORRECTED analysis below: the flatness is
under-sampling, not non-convergence, and the hats were blind to round 1 by design.**

| hat | r1 | r2 | | hat | r1 | r2 |
|:---|--:|--:|:--|:---|--:|--:|
| 01 consistency-matrix | 3 | 2 | | 07 latex-typesetter | 5 | 2 |
| 02 software-architect | 9 | 10 | | 08 api-user | 5 | 6 |
| 03 spectral-mathematician | 12 | 11 | | 09 normalization-auditor | 2 | 2 |
| 04 differential-geometer | 15 | 17 | | 10 citations-integrity | 3 | 4 |
| 05 gpu-practitioner | 5 | 6 | | 11 style-editor | 6 | 6 |
| 06 structure-consistency | 10 | 11 | | 12 cold-reader | 10 | 10 |
| | | | | **TOTAL** | **85** | **87** |

Round 1 fixed 79 findings. Round 2, same lens, same corpus, found 87.

## Why it does not converge — CORRECTED 2026-08-05

**The first analysis in this file was wrong, and the user's question exposed it: were the hats
pointed at the previous round's fixes, or blind?** They were blind. Nothing in `panel.js` passed
prior findings, the prior summary, or a list of what changed; `.claude/doc-review-prev/` is kept for
the consolidator's diffing, not for the hats. That invalidates the causal story below it.

The original claim was that the panel chases its own tail — that every fix is fresh prose seeding the
next round. **Measured, that term is real but small.** Round 2's 87 break down as:

| class | count | |
|:---|--:|:---|
| findings on prose round 1 *wrote* | ~6 | the treadmill term — **7%**, not the mechanism |
| re-litigation of settled non-defects | 4 | instrument defect, now fixed |
| genuinely new, on prose neither round touched | ~77 | **the actual story** |

Round 1 closed all 85 with **no backlog**. So those ~77 are not deferred work — they are findings
round 1's hats *did not make*. Spot-checked against the round-1 banked files: `fiber-preserving`
(three conflicting meanings), `curl` as "the local rotation rate", `cov` as central-vs-raw second
moment, the duplicate HTML `id`, "three different names for one idea" — **zero** appear in round 1.

Two independent samples of the same lens on essentially the same corpus overlap by roughly 7%.

**That is a statement about sampling, not about convergence.** Twelve hats, each capped at its 25
most significant findings over a ~100-page corpus, *sample* the defect population; they do not
enumerate it. A flat 85 → 87 is what an under-sampled population looks like, not a treadmill.
