#!/usr/bin/env python3
# Seeded-defect calibration for the /check-consistency panel. Ported from GBGIsotropicTurbulence
# 2026-08-27 — the MECHANISM is theirs, the catalog below is PF's own and must stay that way.
#
# THE PROBLEM IT SOLVES: the panel has no denominator. Its output is evidence of YIELD and was being
# read as evidence of COVERAGE — nothing measured recall, so a hat returning nothing was
# indistinguishable from a corpus with nothing wrong. PF has a concrete instance of that conflation:
# the round-6 summary records that the two mathematician anchors "independently re-derived and
# CONFIRMED the core spectral and structural mathematics sound", and that sentence was later used, in
# an argument about instruments, as though it established coverage. It establishes only that two hats
# found nothing.
#
# This injects k known, labeled defects into the consolidated manuscripts BEFORE a round, so the
# round's banked findings carry a measurable per-class recall (computed afterwards by recall.py). A
# class with 0/k seeded recall is then known to be UNMEASURED rather than clean — which is the whole
# point, and is not something yield can ever tell you.
#
#   Usage: seed_defects.py <manuscript_full.md> <manuscript_siteonly.md> <ground_truth.json>
#
# Mutates BOTH manuscripts in place and writes the ground truth. Deterministic: the k-th eligible
# occurrence is chosen by a fixed index, no RNG, so a re-run reproduces the same seeding.
#
# DISCIPLINE, and it matters more than the code: the seeded manuscripts are DISPOSABLE. Never fix the
# real corpus from a seeded finding without checking ground_truth.json first, and the consolidation
# must SUBTRACT seeded hits (recall.py marks them) before the summary is written. A planted defect
# that reaches a real fix pass has corrupted the docs to measure the instrument.
import json, re, sys

FULL, SITE, TRUTH = sys.argv[1], sys.argv[2], sys.argv[3]

# (class, description, anchor regex, replacement, which-occurrence — 1-based)
#
# The catalog is CLASS-shaped: each entry plants a defect of a class some PF hat exists to catch, so
# recall is attributable per hat. Occurrence indices are deliberately not all "first" — the first
# occurrence of a convention is usually its definition site, where a corruption is unrealistically
# easy to spot; a calibration defect belongs mid-corpus. Anchors were verified against the PF doc
# corpus before being committed (counts in the range 5-330), but the manuscript is a rendered subset,
# so the script reports SKIPPED rather than failing when one is not found often enough.
CATALOG = [
    ("normalization", "an energy one-half corrupted to one-third at a single site",
     r"\\tfrac\{1\}\{2\}", r"\\tfrac{1}{3}", 5),
    ("citation-drift", "the Lalescu spline paper's year shifted at one site",
     r"Lalescu, Teaca & Carati \(2010\)", "Lalescu, Teaca & Carati (2012)", 2),
    ("quantifier", "a universal weakened to a false near-universal",
     r"\bat every mode\b", "at almost every mode", 2),
    ("notation", "the upright imaginary unit replaced by the banned bare italic at one site",
     r"\\mathrm\{i\}k", "ik", 7),
    ("stale-name", "a live binding replaced by a name decision 60 removed",
     r"`radial_kernel`", "`squared_wavenumber_field`", 4),
    ("cross-page", "the transfer measure factor inverted at ONE site only",
     r"N/M", "M/N", 3),
    ("weakened-guarantee", "a bitwise guarantee downgraded to a tolerance at one site",
     r"bitwise-identical", "identical to roundoff", 4),
    ("false-property", "an idempotence claim negated at one site",
     r"\bidempotent\b", "non-idempotent", 3),
]


def seed(text, anchor, repl, nth):
    hits = list(re.finditer(anchor, text))
    if len(hits) < nth:
        return None, None, None
    m = hits[nth - 1]
    start, end = m.span()
    page = "?"
    for pm in re.finditer(r"===== PAGE: (.+?) =====", text[:start]):
        page = pm.group(1)
    before = text[max(0, start - 60):min(len(text), end + 60)]
    mutated = text[:start] + repl + text[end:]
    after = mutated[max(0, start - 60):min(len(mutated), start + len(repl) + 60)]
    return mutated, page, (before.strip(), after.strip())


full = open(FULL).read()
site = open(SITE).read()
truth, skipped = [], []
for cls, desc, anchor, repl, nth in CATALOG:
    mutated, page, ctx = seed(full, anchor, repl, nth)
    if mutated is None:
        skipped.append((cls, anchor))
        continue
    full = mutated
    # The siteonly manuscript is a subset of the full one: apply the identical local edit wherever its
    # text carries the same before-context, so the two substrates tell one consistent seeded story. A
    # seed that lands only in `full` is still valid — it is simply invisible to the two site-only hats.
    if ctx[0] in site:
        site = site.replace(ctx[0], ctx[1], 1)
    truth.append({"id": f"seed-{len(truth)+1:02d}", "class": cls, "description": desc,
                  "page": page, "original_context": ctx[0], "mutated_context": ctx[1]})

open(FULL, "w").write(full)
open(SITE, "w").write(site)
json.dump({"seeded": truth, "skipped": [c for c, _ in skipped]}, open(TRUTH, "w"), indent=2)
print(f"seeded {len(truth)} defects ({', '.join(t['class'] for t in truth)})")
for cls, anchor in skipped:
    print(f"SKIPPED {cls}: anchor {anchor!r} not found often enough — the catalog needs re-anchoring")
if skipped:
    print("NOTE: a skipped class is NOT measured this round. Its recall is undefined, not zero.")
