#!/usr/bin/env python3
# DOI cross-check — the first of /check-docs' two non-grep backstops, extracted from check-docs.md
# 2026-08-27 for the reason guards.sh exists: a check that depends on who retypes it is not
# deterministic.
#
# THE RULE IT ENFORCES. A docstring carries its reference inline so a REPL reader sees it without
# opening another file, and ARCHITECTURE.md §References carries the canonical copy. Deliberate
# duplication has exactly one risk — drift — so the two must agree VERBATIM, and a DOI is the part
# that can be compared mechanically.
#
# BOTH DIRECTIONS ARE CHECKED, and the second is the one a hand-run sweep forgets: a DOI in a
# docstring but not in §References means the canonical list is incomplete; a DOI in §References but
# in no docstring is not itself a defect (a reference may be cited by a design doc alone), so it is
# reported separately and as information rather than as a failure.
#
#   Usage: doi_crosscheck.py [repo-root]      exit 1 if a docstring DOI is missing from §References
import glob, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
os.chdir(root)

DOI = re.compile(r"doi\.org/[^\s\)\]\"]+")


def dois(text):
    return {m.rstrip(".,);") for m in DOI.findall(text)}


src_dois = {}
for f in sorted(glob.glob("src/*.jl")):
    for d in dois(open(f, errors="replace").read()):
        src_dois.setdefault(d, []).append(os.path.basename(f))

arch_text = open("docs/ARCHITECTURE.md", errors="replace").read()
arch_dois = dois(arch_text)

missing = sorted(d for d in src_dois if d not in arch_dois)
unused = sorted(d for d in arch_dois if d not in src_dois)

for d in missing:
    print(f"MISSING from ARCHITECTURE §References: {d}   (cited in {', '.join(sorted(set(src_dois[d])))})")
for d in unused:
    print(f"  info: in §References, cited by no docstring: {d}")
print(f"\n{len(src_dois)} DOI(s) in docstrings, {len(arch_dois)} in §References, {len(missing)} missing.")
sys.exit(1 if missing else 0)
