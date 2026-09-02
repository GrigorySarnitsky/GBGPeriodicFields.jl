#!/usr/bin/env python3
"""A sentence must open with a capitalized ordinary word — never a lowercase code identifier or a formula.

The rule is in `CLAUDE.md` §Style. A lowercase start is the defect, so the fix is to REWORD so an
ordinary word leads (`` `divergence` uses this kernel`` -> "The `divergence` operator uses this
kernel"), never to capitalize the identifier, whose binding is lowercase by nature.

WHY THIS IS A SCRIPT AND NOT A GREP. The scan this replaces was `grep -E '\\. (`[a-z]|``)'`, which
requires a period, a space and the opener to sit on ONE line. Prose here is hard-wrapped and full of
paragraph breaks, so the two commonest shapes of the defect were invisible to it:

    ...ends the previous sentence.                 <- period is the last thing on ITS line
    `destination` and `source` are two sections    <- opener starts the NEXT line

and a paragraph-initial opener, which has no preceding period anywhere near it. Both were live in the
corpus on 2026-09-02 — nine of them, including one in a docstring rendered on the API site and one the
user found by reading the page. This is the SECOND time this scan has been found narrower than the
rule it enforces: `guards.sh` records a 2026-09-01 fix for it having scanned `src/` while its spec said
`src/` and the doc pages, and that time it had reported the class clean over surfaces it never opened.
A check narrower than it appears is worse than an absent one, because it is believed.

So a sentence start is computed rather than pattern-matched: after `. ` within a line, after a line
that ENDS a sentence, and after a blank line.

Exemptions are the rule's own, not conveniences: a bullet or list item (a fragment by rule — §13
decision entries and argument-doc bullets included), a `#` code comment, a Markdown heading, anything
inside a fenced code block, an indented line (a docstring signature or a continuation), the
`e.g.`/`i.e.`/`cf.`/`vs.`/`incl.` abbreviations, and a ``\\checkmark`` status marker, which is a marker
rather than prose.

    python3 .claude/commands/check-docs/sentence_openers.py [--verbose]

Prints one line per hit and a count. Like the grep it replaces this is TRIAGE, never a gate: it exits
0 even with hits, because judging an opener needs a reader. It exits 1 only if it scanned nothing,
so a parser broken by a refactor fails loudly instead of reporting a clean corpus.
"""
import glob
import re
import sys
from pathlib import Path

LEADER = re.compile(r'^\s*([-*+>|]|\d+[.)])\s')       # bullet / list / quote / table row
FENCE = re.compile(r'^\s*```')
HEADING = re.compile(r'^\s*#')
OPENER = re.compile(r'(`[a-z_][\w!]*`|``[^`])')       # lowercase code span, or a math span
ENDS_SENTENCE = re.compile(r'[.!?]\*{0,2}["\')]?$')
ABBREV = re.compile(r'(e\.g|i\.e|cf|vs|incl)\.\s*$', re.I)
CHECKMARK = re.compile(r'^``\\checkmark``')


def surfaces():
    docs = ["docs/ARCHITECTURE.md", "docs/FORMALIZATION.md", "docs/TESTING.md", "docs/PERFORMANCE.md",
            "docs/src/notation.md", "docs/src/index.md", "docs/src/tutorial.md", "docs/src/api.md"]
    docs += sorted(glob.glob("docs/src/api/*.md"))
    docs += ["examples/HIST_CPU.jl"] + sorted(glob.glob("examples/gpu/*/*.jl"))
    return sorted(glob.glob("src/*.jl")) + [d for d in docs if Path(d).exists()]


def prose_lines(path):
    """Yield (lineno, line, previous_line) for PROSE lines only.

    A `.jl` surface is prose only inside a `\"\"\"` docstring; a `.md` surface is prose outside fences.
    The Literate examples are `.jl` but their prose is `# ` comments, so they are read as Markdown-like
    and their comment marker is stripped before the line is judged.
    """
    literate = path.startswith("examples/")
    in_docstring = path.endswith(".jl") and not literate
    active, fenced, previous = not in_docstring, False, ""
    for number, raw in enumerate(Path(path).read_text().split("\n"), 1):
        line = raw
        if literate:
            if not raw.startswith("# "):
                previous = ""
                continue
            line = raw[2:]
        if in_docstring and line.strip().startswith('"""'):
            active, previous = not active, ""
            continue
        if FENCE.match(line):
            fenced = not fenced
            previous = line
            continue
        if active and not fenced:
            yield number, line, previous
        previous = line


def hits_in(path):
    """Every sentence in this surface that opens with a lowercase identifier or a formula."""
    found = []
    in_list_item = False
    for number, line, previous in prose_lines(path):
        # A wrapped CONTINUATION of a bullet is still that bullet, and the rule exempts list items —
        # §13 decision-log entries above all, which run for paragraphs and are append-only history.
        # Without this the scan reports them every run, and a column of standing non-defects is a
        # column that stops being read.
        if LEADER.match(line):
            in_list_item = True
        elif not line.strip() or not line.startswith((" ", "\t")):
            in_list_item = False
        if HEADING.match(line) or LEADER.match(line) or in_list_item:
            continue
        stripped = line.rstrip()
        # (1) opener at the START of the line: a sentence starts here if the previous line ended one,
        # or if this begins a paragraph. An indented line is a signature or a wrapped continuation.
        if not line.startswith((" ", "\t")) and OPENER.match(line) and not CHECKMARK.match(line):
            if previous.strip() == "" or (ENDS_SENTENCE.search(previous.rstrip())
                                          and not ABBREV.search(previous.rstrip())):
                found.append((number, stripped[:100]))
                continue
        # (2) opener AFTER a period within the line — the case the old grep covered.
        for match in re.finditer(r'(?<!\.)\.\s+(`[a-z_][\w!]*`|``[^`])', line):
            before = line[:match.start() + 1].rstrip()
            if ABBREV.search(before) or "checkmark" in line:
                continue
            found.append((number, stripped[:100]))
            break
    return found


def main(verbose=False):
    total = scanned = 0
    for path in surfaces():
        scanned += 1
        for number, text in hits_in(path):
            print(f"  {path}:{number}: {text}")
            total += 1
    if scanned == 0:
        print("DEAD LANE: no surface matched — the scan is not measuring anything.")
        return 1
    if verbose or total:
        print(f"  {total} sentence opener(s) over {scanned} surfaces "
              f"(TRIAGE — read each; bullets, markers and abbreviations are exempt by rule)")
    return 0


if __name__ == "__main__":
    sys.exit(main(verbose="--verbose" in sys.argv))
