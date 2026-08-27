#!/usr/bin/env python3
"""Coverage check for a verification round — the measurement behind the tally.

A workflow script cannot see the filesystem, so nothing inside verify.js or verify-fixes.js can
confirm that a lane actually WROTE its verdict file, or that the file covers every banked finding.
This does that from outside, and it is a MANDATORY post-step: a tally is not a closure rate until
this passes.

Ported from GBGIsotropicTurbulence 2026-08-27, whose header records the two failures it was built
for — both of which PF was exposed to:

  * A lane returning an EMPTY structured result while having written a full verdict file, so its
    verdicts were silently missing from the tally.
  * The verifier's hat list naming fewer hats than the panel banked, so hats were never verified
    while the run still reported success. PF's HATS array is hardcoded in THREE files (panel.js,
    verify.js, verify-fixes.js) and a workflow script cannot glob the pile to check itself — so
    this external comparison is the only thing standing between that duplication and a silent
    partial verification.

    python3 coverage.py <pile-dir> [subdir]      # subdir: closure (verify-fixes) or state (verify)

Exit 1 when any hat is unverified, short, or missing — so it can gate a "converged" claim.
"""
import re, sys, glob, os

pile = sys.argv[1] if len(sys.argv) > 1 else '.claude/doc-review'
sub = sys.argv[2] if len(sys.argv) > 2 else 'closure'
verdict_dir = os.path.join(pile, sub)

# The heading delimiter is OPTIONAL. Hats write "## 3. Title", "## Finding 3 — Title" and bare
# "## Finding 3"; IT records that requiring punctuation after the number made one hat parse to ZERO
# findings while it had banked eleven — and since a hat with 0 banked needs 0 verdicts, it then
# passed the gate as "ok". A hat that parses to nothing is an ERROR here, never a pass.
FINDING = re.compile(r'^#{2,4} +(?:Finding +)?(\d+)(?=[.:)\s—-]|$)', re.M)
# Both PF verdict vocabularies, and both renderings agents actually produce — "VERDICT: LINE-ONLY"
# and a standalone "**LINE-ONLY**". IT records demanding the literal word VERDICT reporting a
# complete 21/21 hat as SHORT by 21; a coverage gate that cries wolf is one the operator learns to
# wave through, which is the failure it exists to prevent.
TOKEN = (r'(?:HONORED|LINE-ONLY|NEW-DEFECT|SCOPE-CREEP|UNDONE|LAUNDERED'
         r'|PRESENT|ABSENT|UNCLEAR|NEVER-A-DEFECT)')
VERDICT = re.compile(r'(?:VERDICT[:*\s]*\**\s*' + TOKEN + r'|^\s*\**' + TOKEN + r'\**\s*$)', re.I | re.M)

banked = sorted(p for p in glob.glob(os.path.join(pile, '[0-9][0-9]-*.md'))
                if not os.path.basename(p).startswith('00-'))
if not banked:
    print(f'NO BANKED FINDINGS under {pile} — nothing to verify, and that is not a pass.')
    sys.exit(1)

bad = 0
print(f'{"HAT":<40} {"FINDINGS":>8} {"VERDICTS":>8}  STATUS')
for path in banked:
    name = os.path.basename(path)
    n_find = len(set(FINDING.findall(open(path, errors='replace').read())))
    vpath = os.path.join(verdict_dir, name)
    if not os.path.exists(vpath):
        print(f'{name:<40} {n_find:>8} {"-":>8}  MISSING — never verified')
        bad += 1
        continue
    n_verd = len(VERDICT.findall(open(vpath, errors='replace').read()))
    if n_find == 0:
        print(f'{name:<40} {n_find:>8} {n_verd:>8}  PARSED TO ZERO — the file is unreadable to this '
              f'gate, which is an error, not a clean hat')
        bad += 1
    elif n_verd < n_find:
        print(f'{name:<40} {n_find:>8} {n_verd:>8}  SHORT by {n_find - n_verd} — those are UNVERIFIED, not clean')
        bad += 1
    else:
        print(f'{name:<40} {n_find:>8} {n_verd:>8}  ok')

# The hole this exists for: a verdict file with no banked counterpart means the verifier's hardcoded
# hat list and the panel's have diverged.
orphans = [os.path.basename(p) for p in glob.glob(os.path.join(verdict_dir, '[0-9][0-9]-*.md'))
           if not os.path.exists(os.path.join(pile, os.path.basename(p)))]
for o in orphans:
    print(f'{o:<40} {"-":>8} {"?":>8}  ORPHAN — verified but never banked; the hat lists have diverged')
    bad += 1

print()
print(f'{len(banked)} banked hat(s), {bad} problem(s).'
      + ('' if bad else '  Coverage complete — the tally may be read as a rate.'))
sys.exit(1 if bad else 0)
