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
import json, glob, os, re, sys

TRUTH, PILE = sys.argv[1], sys.argv[2]
truth = json.load(open(TRUTH))["seeded"]


def fragments(seed):
    mut = seed["mutated_context"]
    # Distinctive pieces of the mutation itself (not the shared context): the tokens present in
    # mutated_context and absent from original_context.
    orig_tokens = set(re.findall(r"\S+", seed["original_context"]))
    frags = [t for t in re.findall(r"\S+", mut) if t not in orig_tokens and len(t) >= 4]
    return frags or [mut[:40]]


hits = {s["id"]: [] for s in truth}
for path in sorted(glob.glob(os.path.join(PILE, "[0-9][0-9]-*.md"))):
    hat = os.path.basename(path)
    text = open(path).read()
    for s in truth:
        if any(f in text for f in fragments(s)):
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
