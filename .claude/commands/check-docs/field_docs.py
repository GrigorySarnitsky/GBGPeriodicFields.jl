#!/usr/bin/env python3
"""A documented field name must be a field the struct actually has, and every field must be documented.

The rubric's shape rule 2 says a type storing named, user-readable fields documents them under
`The fields are`, one bullet per field. Nothing checked that the bullets still MATCH the struct, and
on 2026-09-02 they did not: `PointSet`'s field was renamed `coordinates` -> `positions` in the code
and the docstring kept the old name in both its signature line and its field bullet, so the rendered
page told a reader to write `point_set.coordinates`, which throws.

That defect is invisible to every other guard. The build does not read prose, `checkdocs = :exports`
only asks whether a docstring EXISTS, and a grep for the old name cannot separate a stale identifier
from the ordinary English word it also is -- which is exactly why this one survived a rename sweep
that was otherwise clean across all nine identifiers.

Both directions are checked, because they fail differently. A GHOST bullet (documented, not real) is
the user-facing defect: it names an accessor that does not exist. An UNDOC field (real, no bullet) is
the rubric violation, and is also what a half-applied rename leaves behind -- the `PointSet` slip
produced one of each.

Silent when clean, so it drops straight into `guards.sh`'s `hard` helper. It reports a finding when
it matches NO types at all, so a parser that has been broken by a refactor fails loudly instead of
passing vacuously -- the missing case is the failing case.

    python3 .claude/commands/check-docs/field_docs.py [--verbose]

Exit 0 clean, 1 on any mismatch.
"""
import glob
import re
import sys
from pathlib import Path

# A bullet names its field in backticks, optionally with the type: `positions`, `grid::G`,
# `**first_kernel**`. Identifiers may be Unicode (`_MapValues` has a field spelled with a Greek phi),
# so the name class is "not whitespace, backtick, colon or comma" rather than an ASCII letter class.
BULLET = re.compile(r"^\s*[-*]\s")
NAME_IN_BULLET = re.compile(r"`([^`:\s,]+)(?:::[^`]*)?`")
FIELD_DECL = re.compile(r"^\s{2,}([^\s:=]+)\s*::")
DOC_THEN_STRUCT = re.compile(r'"""\n(.*?)\n"""\n(?:mutable )?struct\s+([^\s{<]+)', re.S)


def documented_fields(doc):
    """The field names the docstring's `The fields are` list claims, or None if it has no such list."""
    start = doc.find("The fields are")
    if start < 0:
        return None
    names, in_list = [], False
    for line in doc[start:].split("\n")[1:]:
        if BULLET.match(line):
            in_list = True
            # Cut at the em dash: the prose AFTER it routinely backticks other identifiers
            # (a type, a sibling function), and those are not this bullet's field.
            names += [m.group(1) for m in NAME_IN_BULLET.finditer(line.split("—")[0])]
        elif in_list and line.strip() and not line.startswith((" ", "\t")):
            break  # a new top-level paragraph ends the list
    return names


def real_fields(body):
    """The struct's own field names, stopping at an inner constructor."""
    out = []
    for line in body.split("\n"):
        if re.match(r"^\s*function", line):
            break
        if re.match(r"^\s*#", line):
            continue
        match = FIELD_DECL.match(line)
        if match:
            out.append(match.group(1))
    return out


# A documented type whose fields are deliberately NOT listed under `The fields are`, with the reason.
# Shape rule 2 asks for the bulleted form for "named, user-readable fields"; these three are not that,
# and forcing a list on them would make the docs worse rather than better.
NO_FIELD_LIST = {
    "FieldSpectralMultipliers":
        "its fields ARE documented, in prose: the eight arrays are the constructor arguments, already "
        "bulleted above as arguments (\"every argument above is stored under its own name\"), and the "
        "six decision-70 broadcast views are described as one internal group. Fourteen bullets would "
        "duplicate the argument list and promote six internals to a public-looking surface.",
    "NUFFT":
        "a plan, not a record: its thirteen fields are oversampled grids, FFT plans, a deconvolution "
        "window and embedding maps, none of which a caller may touch. Its user-facing surface is its "
        "constructor arguments, which the docstring documents as arguments.",
    "_FiberGather":
        "an internal `_`-prefixed helper, which the rubric already exempts from the argument-shape "
        "rules for the same reason.",
}


def main(verbose=False):
    findings, checked = [], 0
    for path in sorted(glob.glob("src/*.jl")) + sorted(glob.glob("ext/*.jl")):
        source = Path(path).read_text()
        for match in DOC_THEN_STRUCT.finditer(source):
            doc, name = match.group(1), match.group(2)
            documented = documented_fields(doc)
            if documented is None:
                # A type with fields and NO list at all. The original check skipped these entirely,
                # which is how `PointTraversalOrder` shipped without documenting `indices` — a field
                # the tests, the benchmarks and the docstring's own prose all read. A check that
                # validates a list only when the list exists cannot see a missing list.
                body = source[match.end():]
                body = body[:body.find("\nend")]
                if real_fields(body) and name not in NO_FIELD_LIST:
                    findings.append(f"NOLIST {name} ({path}): stores {real_fields(body)} but has no "
                                    f"`The fields are` list — add one, or record why not")
                continue
            checked += 1
            body = source[match.end():]
            body = body[:body.find("\nend")]
            real = real_fields(body)
            ghost = [d for d in documented if d not in real]
            missed = [r for r in real if r not in documented]
            if ghost:
                findings.append(f"GHOST  {name} ({path}): documents {ghost}, which the struct "
                                f"does not have; its fields are {real}")
            if missed:
                findings.append(f"UNDOC  {name} ({path}): field(s) {missed} have no bullet")

    if checked == 0:
        findings.append("DEAD LANE: no documented struct type matched the parser at all — the check "
                        "is not measuring anything. Fix it rather than reading this as clean.")

    # An exemption naming a type that no longer exists is stale, and a stale exemption silently
    # widens the check's blind spot. Every other derived gate in this package checks this; so does
    # this one.
    seen = {m.group(2) for path in sorted(glob.glob("src/*.jl")) + sorted(glob.glob("ext/*.jl"))
            for m in DOC_THEN_STRUCT.finditer(Path(path).read_text())}
    for stale in sorted(set(NO_FIELD_LIST) - seen):
        findings.append(f"STALE  the `{stale}` exemption names no documented struct — drop it")

    for finding in findings:
        print(finding)
    if verbose and not findings:
        print(f"field docs OK: {checked} documented struct types, every bullet a real field")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(verbose="--verbose" in sys.argv))
