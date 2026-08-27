#!/usr/bin/env python3
# Instrument manifests. Format agreed with the IT session 2026-08-27 so either package can diff
# toolboxes in a single read, after divergence went unnoticed three requests running.
#
#   python3 .claude/commands/manifest.py     # regenerate, then commit
#
# PURPOSE IS DERIVED, NEVER TYPED. It is lifted from each file's first substantive comment, so it
# cannot go stale without the file itself going stale — a hand-maintained description is exactly the
# thing that rots, and rot is the failure this exists to prevent. A file whose opening comment does
# not say what it is shows a dash, and that dash is a finding about the file.
#
# ONE DEPARTURE FROM IT'S FORMAT, and it matters for PF specifically. IT writes one manifest per
# instrument DIRECTORY. PF's `/check-docs` has no directory — it is a single 294-line markdown file
# describing a deterministic battery to be run by hand — so a per-directory manifest would omit the
# instrument most in need of visibility, reproducing the blind spot it exists to close. PF therefore
# also writes a ROOT manifest covering the command-level `.md` files, and a command with no directory
# of scripts is flagged there.
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Every extension an instrument can be written in. A missing entry means the file is silently
# absent from its own manifest — which is the staleness this exists to prevent, so the table is
# checked whenever a new kind of script lands. `.sh` was missing when guards.sh was added.
COMMENT = {".py": "#", ".js": "//", ".jl": "#", ".sh": "#", ".md": None}


def changed(path):
    try:
        out = subprocess.run(["git", "log", "-1", "--format=%cs", "--", path],
                             cwd=ROOT, capture_output=True, text=True).stdout.strip()
        return out or "untracked"
    except Exception:
        return "?"


def purpose(path):
    ext = os.path.splitext(path)[1]
    marker = COMMENT.get(ext)
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return "-"
    # A command file may open with YAML frontmatter, whose `description:` IS its purpose — that is
    # what the harness itself shows for the command, so anything else would be a second description
    # to keep in step, which is the failure this manifest exists to avoid.
    if ext == ".md" and lines and lines[0].strip() == "---":
        for line in lines[1:40]:
            if line.strip() == "---":
                break
            if line.strip().startswith("description:"):
                return line.split(":", 1)[1].strip().strip("\"'")
    for line in lines[:40]:
        s = line.strip()
        if not s or s == "---":
            continue
        if ext == ".md":
            # Prefer the H1 title; a mid-document heading is NOT the file's purpose (check-docs.md has
            # no H1 and was reporting its "Cost modes" section), so fall back to the opening prose.
            if s.startswith("# "):
                return s.lstrip("#").strip()
            if s.startswith("#"):
                continue
            return re.sub(r"[*`_]", "", s)
        
        if s.startswith("#!"):
            continue
        if marker and s.startswith(marker):
            body = s[len(marker):].strip()
            # Skip decoration and section banners; take the first line that says something.
            if len(body) >= 12 and not set(body) <= set("-=#*/ "):
                return body
    return "-"


def write(dirpath, title, files):
    rows = []
    for f in sorted(files):
        p = os.path.join(dirpath, f)
        rows.append((f, changed(p), purpose(p)))
    width = max([len(r[0]) for r in rows] + [4]) + 2
    out = [f"# {title} — instrument manifest", "#",
           "# One line per file: name, the date git last changed it, and its purpose.",
           "# Regenerate with `python3 .claude/commands/manifest.py` and commit the result.",
           "# PURPOSE is DERIVED from each file's first substantive comment — never typed, so it cannot",
           "# go stale on its own. A dash means the file does not say what it is, which is a finding.",
           "# Format agreed with the IT session 2026-08-27 so either package can diff toolboxes in one read.",
           "",
           f"{'FILE'.ljust(width)}{'CHANGED'.ljust(13)}PURPOSE"]
    for f, c, p in rows:
        out.append(f"{f.ljust(width)}{c.ljust(13)}{p[:96]}")
    target = os.path.join(dirpath, "MANIFEST.txt")
    open(target, "w").write("\n".join(out) + "\n")
    return target, len(rows)


written = []
# One manifest per instrument directory.
for name in sorted(os.listdir(ROOT)):
    d = os.path.join(ROOT, name)
    if not os.path.isdir(d):
        continue
    files = [f for f in os.listdir(d) if os.path.splitext(f)[1] in COMMENT and f != "MANIFEST.txt"]
    if files:
        written.append(write(d, name, files))

# Plus the root manifest, so a command with no script directory is still visible.
root_md = [f for f in os.listdir(ROOT) if f.endswith(".md")] + ["manifest.py"]
written.append(write(ROOT, "commands", root_md))

for target, n in written:
    print(f"  {os.path.relpath(target, ROOT)}: {n} files")
# The thing IT's per-directory form cannot say: which commands have no scripts at all.
bare = [f[:-3] for f in os.listdir(ROOT)
        if f.endswith(".md") and not os.path.isdir(os.path.join(ROOT, f[:-3]))]
if bare:
    print(f"  NOTE: command(s) with no script directory — every check is run by hand: {', '.join(sorted(bare))}")
