#!/usr/bin/env python3
"""THE DISPOSITION GATE — has this audit been answered, and does it still describe the tree?

Ported from GBGIsotropicTurbulence 2026-08-27. The audit's findings are JUDGEMENTS, and judgements get
quietly dropped — which is the whole reason the sibling instruments carry an adversarial verifier.
This tool deliberately does NOT carry one: /audit-changes already contains its own mechanical anchor
(the `executing` lane RUNS things), and a second adversarial layer auditing the auditor is where the
regress begins and the grounding ends.

What replaces it is this gate, which asks the two questions a program can answer:

  1. Has every SERIOUS finding been ANSWERED? Not fixed — ANSWERED. A disposition may be "fixed",
     "refused, because ...", or "escalated to the user", but it may NOT be absent. An absent
     disposition is a dropped finding, and dropping findings is the failure the sibling verifiers
     exist to catch.

  2. Does the audit still describe the current tree? An audit that read an older commit certifies
     nothing about the code as it stands. This is the check that makes "we audited it" mean something
     a week later.

    python3 gate.py [path/to/audit.json]      default: .claude/audit-changes/latest.json

Exit 0 answered and current; 1 a finding is unanswered or the audit is stale; 2 no audit on record.
"""
import json, os, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True).stdout.strip() or "."
DEFAULT = os.path.join(ROOT, ".claude", "audit-changes", "latest.json")
ANSWERS = ("fixed", "refused", "escalated")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.exists(path):
        print(f"NO AUDIT ON RECORD at {path}.")
        print("An unaudited change set is not a clean one — run the audit before claiming it is.")
        sys.exit(2)

    audit = json.load(open(path))
    problems = []

    # ---- 1. staleness, against the paths the audit says it covered ------------------------------
    covered = audit.get("covered_paths") or ["src"]
    head = subprocess.run(["git", "-C", ROOT, "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    audited = audit.get("head")
    if not audited:
        problems.append("the audit records no HEAD, so it cannot be checked against the tree at all")
    elif audited != head:
        r = subprocess.run(["git", "-C", ROOT, "diff", "--name-only", audited, "HEAD", "--"] + covered,
                           capture_output=True, text=True)
        # A FAILED diff must never read as "nothing changed". If the audited commit is unreachable —
        # rebased away, dropped, from another clone — git errors and prints nothing to stdout, and the
        # empty result is indistinguishable from a clean comparison. That inversion made a stale audit
        # PASS when this gate was first falsified: the safest-looking outcome arriving precisely when
        # the audit cannot be checked at all.
        if r.returncode != 0:
            problems.append(f"UNCHECKABLE: the audited commit {audited[:8]} is not reachable in this "
                            f"repository, so the audit cannot be compared against the tree "
                            f"({r.stderr.strip().splitlines()[0] if r.stderr.strip() else 'git failed'})")
            moved = []
        else:
            moved = r.stdout.split()
        if moved:
            problems.append(f"STALE: {len(moved)} covered file(s) changed since the audit ({audited[:8]} -> {head[:8]})")
            for f in moved[:20]:
                problems.append(f"    {f}")
        else:
            print(f"note: HEAD moved {audited[:8]} -> {head[:8]}, but no covered file changed — audit still current.")

    # ---- 2. every serious finding answered ------------------------------------------------------
    dispositions = audit.get("dispositions") or {}
    serious = [c for c in audit.get("concerns", []) if c.get("severity") == "serious"]
    # A regression — a concern naming input that previously worked — is treated as serious whatever
    # the lane called it. That field is the one this instrument exists to surface, so its severity is
    # not the reporting lane's to downgrade.
    for c in audit.get("concerns", []):
        if (c.get("previously_worked") or "").strip() and c not in serious:
            serious.append(c)

    for c in serious:
        title = c.get("title", "?")
        d = (dispositions.get(title) or "").strip()
        if not d:
            problems.append(f"UNANSWERED: [{c.get('lane','?')}] {title}")
        elif not d.lower().startswith(ANSWERS):
            problems.append(f"NOT A DISPOSITION: [{c.get('lane','?')}] {title} -> {d!r} "
                            f"(must begin 'fixed', 'refused, because ...' or 'escalated')")
        elif d.lower().startswith("refused") and len(d) < 24:
            problems.append(f"REFUSAL WITHOUT A REASON: [{c.get('lane','?')}] {title} -> {d!r}")

    if audit.get("deadLanes"):
        problems.append(f"{audit['deadLanes']} lane(s) died in the audit — those lenses are UNAPPLIED, "
                        f"not clean, and the audit is incomplete until they are re-run")

    print(f"{len(serious)} finding(s) requiring an answer; {len(dispositions)} disposition(s) on record.")
    if problems:
        print("\nGATE FAILED:")
        for p in problems:
            print(f"  {p}")
        sys.exit(1)
    print("GATE PASSED — every serious finding answered, and the audit still describes the tree.")
    sys.exit(0)


main()
