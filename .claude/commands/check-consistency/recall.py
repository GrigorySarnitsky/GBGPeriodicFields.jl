#!/usr/bin/env python3
# The read-back half of seeded-defect calibration (C7/C13): given the ground truth seed_defects.py
# wrote and the panel's banked pile, report per-class and per-hat recall, and list every banked
# finding that matches a seeded defect so the consolidation can SUBTRACT it (a seeded hit must
# never reach the real summary, and a real fix must never be driven by a planted defect).
#
#   Usage: recall.py <ground_truth.json> <pile_dir>
#
# Matching is deliberately generous-then-reviewed: a hat detects a seed if its banked file quotes a
# distinctive fragment of the MUTATED text, or names the seed's page while quoting the mutated
# value. The printed match list is for hand review — the recall number is only as honest as the
# matches, so read them.
# THE THREE ARMS THAT VALIDATE THIS SCRIPT. Re-run all three after ANY change to `fragments()` — the
# arms test that function specifically, and a differently-written one can pass two and fail the third.
#
#   ARM A  empty pile                          -> 0 detected, every seed MISSED
#   ARM B  one hat quoting ONE mutation        -> exactly 1 detected, attributed to that hat
#   ARM C  one hat quoting the ORIGINALS       -> 0 detected
#
# A and B check that recall is not falsely LOW. **C checks that it is not falsely HIGH**, and that is
# the one that matters most, because a false positive credits the panel for finding a defect nobody
# planted — it flatters, so nobody reading the number questions it. C was contributed by IT and PF
# FAILED it on first run: whitespace tokenising made `bitwise-identical` one token, so the mutation's
# standalone `identical` read as new while being a substring of the original, and a quote of unmutated
# text scored a detection. The containment test below is substring, not token-membership, for exactly
# that reason.
import json, glob, os, re, sys

TRUTH, PILE = sys.argv[1], sys.argv[2]
_gt = json.load(open(TRUTH))
truth = _gt["seeded"]
# A class whose anchor was not found was never planted, so its recall is UNDEFINED — not zero, and
# above all not absent. Reading only "seeded" dropped it from the report entirely and left the
# per-class table looking as though every catalogued class had been measured: the instrument built to
# stop yield being read as coverage, doing exactly that. Found by PF and IT independently, 2026-08-27.
skipped = _gt.get("skipped", [])


def fragments(seed):
    mut, orig = seed["mutated_context"], seed["original_context"]
    # Distinctive pieces of the MUTATION, i.e. text that the original does not contain.
    #
    # The test is SUBSTRING containment, not token-set membership, and the difference is the whole of
    # arm C. Splitting on whitespace makes `bitwise-identical` a single token, so the mutation's
    # standalone word `identical` reads as new while being a substring of the original — and PF's
    # `weakened-guarantee` seed was then DETECTED from a quote of unmutated text. That is a false
    # positive in the flattering direction: it credits the panel for finding a defect nobody planted
    # and inflates recall, which is the error least likely to be questioned by whoever reads it.
    frags = [t for t in re.findall(r"\S+", mut) if t not in orig and len(t) >= 4]
    # No distinctive fragment means this seed is UNVERIFIABLE by text matching — say so rather than
    # falling back to a slice of mostly-shared context, which is how a false positive gets in.
    return frags


unverifiable = [s["id"] for s in truth if not fragments(s)]
hits = {s["id"]: [] for s in truth}
for path in sorted(glob.glob(os.path.join(PILE, "[0-9][0-9]-*.md"))):
    hat = os.path.basename(path)
    text = open(path).read()
    for s in truth:
        frags = fragments(s)
        if frags and any(f in text for f in frags):
            hits[s["id"]].append(hat)

print(f"seeded: {len(truth)}   detected: {sum(1 for v in hits.values() if v)}")
print()
by_class = {}
for s in truth:
    detected = hits[s["id"]]
    by_class.setdefault(s["class"], []).append(bool(detected))
    mark = "DETECTED" if detected else "MISSED  "
    print(f"{mark} {s['id']} [{s['class']}] on page '{s['page']}': {s['description']}")
    for h in detected:
        print(f"         found by {h}")
print()
print("per-class recall (a 0/k class is UNMEASURED coverage, not a clean corpus):")
for cls, results in sorted(by_class.items()):
    print(f"  {cls:16s} {sum(results)}/{len(results)}")
for cls in sorted(set(skipped)):
    print(f"  {cls:16s} UNDEFINED — anchor not found, never planted, EXCLUDED from the denominator")
if unverifiable:
    print(f"  !! {len(unverifiable)} seed(s) carry no distinctive fragment and cannot be detected by "
          f"text match: {', '.join(unverifiable)} — re-anchor them; their recall is UNDEFINED too")
print()
measured = len(by_class)
total = measured + len(set(skipped))
print(f"CAVEAT: this run measured {measured} of {total} catalogued classes. "
      f"The other {total - measured} were never planted and are not evidence of anything.")
