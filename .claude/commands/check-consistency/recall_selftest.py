#!/usr/bin/env python3
# The self-test for recall.py. Run it after ANY change to that script — especially to `fragments()`,
# which is the only thing these arms actually exercise:
#
#   python3 .claude/commands/check-consistency/recall_selftest.py
#
# WHY THIS IS A SCRIPT AND NOT A NOTE IN A HEADER. The arms began as an instruction to re-run them by
# hand, which is the same shape as every other defect this pair of instruments has produced: a rule
# addressed to the person it constrains. An executable self-test is checked by running it.
#
# WHY THE FIXTURES ARE BUILT HERE RATHER THAN SEEDED FROM THE CATALOG. IT put it best, after its own
# arm C passed and it wrote that pass into a header as evidence the mechanism was sound:
#
#     A test passing over a catalog is a property of the CATALOG, not of the code.
#
# PF's arm C exercises the hyphenated-token case ONLY because `bitwise-identical` happens to be in
# PF's catalog today. Drop that seed and the arm keeps passing while covering nothing — silently. So
# every fixture below is constructed in this file and depends on no catalog entry.
#
#   ARM A  empty pile                      -> 0 detected
#   ARM B  one hat quoting ONE mutation     -> exactly 1, attributed to that hat
#   ARM C  one hat quoting the ORIGINALS    -> 0 detected
#   ARM D  hyphenated original, quoted      -> 0 detected   (the false positive both packages shipped)
#
# A and B check recall is not falsely LOW. C and D check it is not falsely HIGH — the direction that
# flatters, and therefore the one nobody reading the number questions. D is C's targeted form: the
# whitespace-token bug made a standalone word look absent from a hyphenated original, so a quote of
# unmutated text scored a detection. Contributed by IT, which built it after PF traced the mechanism,
# and which failed it.
import json, os, re, subprocess, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RECALL = os.path.join(HERE, "recall.py")


def run(truth, pile_files):
    """Write a ground truth and a pile, run recall.py, return (detected, stdout)."""
    d = tempfile.mkdtemp()
    try:
        pile = os.path.join(d, "pile")
        os.makedirs(pile)
        tp = os.path.join(d, "truth.json")
        json.dump(truth, open(tp, "w"))
        for name, body in pile_files.items():
            open(os.path.join(pile, name), "w").write(body)
        out = subprocess.run([sys.executable, RECALL, tp, pile],
                             capture_output=True, text=True).stdout
        m = re.search(r"detected:\s*(\d+)", out)
        return (int(m.group(1)) if m else -1), out
    finally:
        shutil.rmtree(d, ignore_errors=True)


def seed(sid, cls, original, mutated):
    return {"id": sid, "class": cls, "description": cls, "page": "p",
            "original_context": original, "mutated_context": mutated}


PLAIN = [seed("seed-01", "normalization",
              "the prefactor is one half of the total energy",
              "the prefactor is one third of the total energy"),
         seed("seed-02", "citation-drift",
              "as shown by Lalescu, Teaca & Carati (2010) for the spline",
              "as shown by Lalescu, Teaca & Carati (2012) for the spline")]
# The targeted case: the ORIGINAL carries a hyphenated token whose second half is a standalone word
# in the mutation. Whitespace tokenising makes them look unrelated; substring containment does not.
HYPHEN = [seed("seed-01", "weakened-guarantee",
               "the restart is bitwise-identical to the continued run",
               "the restart is identical to roundoff to the continued run")]

failures = []


def check(arm, expected, detected, out, note):
    ok = detected == expected
    print(f"  ARM {arm}: expected {expected} detected, got {detected} — {'PASS' if ok else 'FAIL'}  ({note})")
    if not ok:
        failures.append((arm, expected, detected, out))


d, o = run({"seeded": PLAIN, "skipped": []}, {})
check("A", 0, d, o, "empty pile")

d, o = run({"seeded": PLAIN, "skipped": []},
           {"03-spectral-methods-mathematician.md": "## Finding 1\n" + PLAIN[1]["mutated_context"]})
attributed = "03-spectral-methods-mathematician" in o
check("B", 1, d, o, f"one mutation quoted; attributed={attributed}")
if not attributed:
    failures.append(("B-attribution", "named hat", "not named", o))

d, o = run({"seeded": PLAIN, "skipped": []},
           {"01-consistency-matrix.md": "\n\n".join(s["original_context"] for s in PLAIN)})
check("C", 0, d, o, "originals quoted — must NOT count as detections")

d, o = run({"seeded": HYPHEN, "skipped": []},
           {"01-consistency-matrix.md": "## Finding 1\n" + HYPHEN[0]["original_context"]})
check("D", 0, d, o, "hyphenated original quoted — the false positive both packages shipped")

# The skipped-class path: an unanchored class must be NAMED and reported UNDEFINED, never dropped.
d, o = run({"seeded": PLAIN, "skipped": ["dimensional-analysis"]}, {})
undefined_ok = "dimensional-analysis" in o and "UNDEFINED" in o
caveat_ok = "measured 2 of 3" in o
print(f"  SKIPPED: class named and UNDEFINED={undefined_ok}, denominator caveat={caveat_ok} — "
      f"{'PASS' if undefined_ok and caveat_ok else 'FAIL'}")
if not (undefined_ok and caveat_ok):
    failures.append(("SKIPPED", "named + UNDEFINED + caveat", f"{undefined_ok}/{caveat_ok}", o))

print()
if failures:
    print(f"SELFTEST FAILED — {len(failures)} arm(s):")
    for arm, exp, got, out in failures:
        print(f"  {arm}: expected {exp}, got {got}")
        print("   " + "\n   ".join(out.strip().splitlines()[:6]))
    sys.exit(1)
print("SELFTEST PASSED — all arms, plus the skipped-class path.")
