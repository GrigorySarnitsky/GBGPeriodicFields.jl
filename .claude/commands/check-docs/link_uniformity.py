#!/usr/bin/env python3
"""Sibling names in one list are all linked or all plain — never a mix.

`CLAUDE.md`'s cross-referencing clause (3a). An odd one out in a short enumeration reads as a broken
link rather than as a rule, which is what the user reported twice on 2026-09-02: `SpectralKernel`
naming `Convolution` bare beside a linked `DifferentialOperators` and `Reductions`, and `FieldAlgebra`
writing ``[`add!`](@ref) and `subtract!` `` then ``([`multiply!`](@ref), `divide!`, `*`, `/`)``.

Both were the "link a target at most once per docstring" rule firing CORRECTLY — the bare name had
been linked earlier, or was judged not worth a second chip. Correct-by-rule is not the point when the
rendered result looks like a defect, so this checks the rendered shape instead of the rule.

WHY THE UNIT IS AN ADJACENT RUN. A first version flagged any bare public name sharing a bullet or a
sentence with a linked one and reported 56 hits, nearly all of them the at-most-once rule working as
intended over a hundred-word paragraph. Narrowed to items separated only by a list separator — `,`,
`and`, `or`, `/` — it reports 7, and all 7 were real. A check whose false positives outnumber its
findings is a check that stops being read, so the narrow unit is the check, not a convenience.

Two exclusions carry weight. An OPERATOR (`+`, `-`, `*`, `/`, `⋅`) is bare by a recorded style choice
— the glyph reads better unlinked — so a run mixing an operator with a linked verb is correct. And a
docstring's OWN binding is never linked, so a run naming it beside a linked sibling is correct too;
without this the check would demand exactly what the rule forbids.

The public surface is read from the `export` lists in `src/`, so this needs no Julia and stays fast
enough for `guards.sh`.

    python3 .claude/commands/check-docs/link_uniformity.py [--verbose]

Exit 0 clean, 1 on any mixed run, and 1 if it finds no exports at all — a parser broken by a refactor
must fail loudly rather than report a clean corpus.
"""
import glob
import re
import sys
from pathlib import Path

# An item in a run: either an @ref link or a bare code span.
ITEM = r'(?:\[`[A-Za-z_]\w*!?`\]\(@ref[^)]*\)|`[A-Za-z_!*/+\-]\w*!?`)'
SEPARATOR = r'(?:,\s+|\s+and\s+|\s+or\s+|\s*/\s*)'
RUN = re.compile(ITEM + r'(?:' + SEPARATOR + ITEM + r')+')
LINKED = re.compile(r'\[`([A-Za-z_]\w*!?)`\]\(@ref')
BARE = re.compile(r'(?<!\[)`([A-Za-z_]\w*!?)`(?!\]\()')


def public_names():
    """Every exported name, read from the `export` lists rather than by loading the package."""
    names = set()
    for path in glob.glob("src/*.jl"):
        text = Path(path).read_text()
        for block in re.finditer(r'^export\s+(.+?)(?=^\s*$|^\w)', text, re.S | re.M):
            for token in re.findall(r'[A-Za-z_]\w*!?', block.group(1)):
                names.add(token)
    return names


def main(verbose=False):
    public = public_names()
    if not public:
        print("DEAD LANE: no `export` list parsed — the check is not measuring anything.")
        return 1

    findings = 0
    for path in sorted(glob.glob("src/*.jl")):
        source = Path(path).read_text()
        for block in re.finditer(r'"""\n(.*?)\n"""', source, re.S):
            doc = " ".join(block.group(1).split())
            head = block.group(1).strip().split("\n")[0].strip()
            own = re.split(r'[({\[ ]', head)[0].strip()
            for run in RUN.finditer(doc):
                text = run.group(0)
                linked = LINKED.findall(text)
                bare = [b for b in BARE.findall(text) if b in public and b != own]
                if linked and bare:
                    findings += 1
                    print(f"  {path}: in `{head[:44]}` — linked {linked}, bare {bare}")
                    print(f"      {text[:104]}")
    if verbose and not findings:
        print(f"link uniformity OK: no mixed run over {len(public)} exported names")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(verbose="--verbose" in sys.argv))
