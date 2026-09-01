#!/usr/bin/env python3
"""Did we ship anything SLOWER? A regression hunt over the committed history of RESULTS.md.

    python3 benchmark/history_regressions.py [threshold]      # default 1.25

Not a prose audit: this reads the measured table at every commit that regenerated it and looks
for (row, column) cells that are materially slower at HEAD than they were earlier, persistently.

It exists because every other layer answers a different question. The canary is a fixed sample of
mechanisms, the born-slow triage asks whether an operation threads and whether it matches its peers,
and a sweep's own write-up compares one archive against one predecessor — so a slow drift, or a step
in a row nobody was watching, is invisible to all three. This reads the whole committed history of
every cell at once. Its first run found finding (am): a 1.45-1.48x regression in the width-8 CPU
scatter that had been shipped for two days, sitting in a table that three instruments had passed.

A cell flagged here is a HYPOTHESIS. Confirm it with a matched A/B against the commit before the
step (the step's date names it), both arms reproducing their own archives, before calling it real:
this table mixes hosts, sweep shapes and measurement regimes, and several documented effects
(finding (y) process history, section 4(u) jitter, finding (ak)'s stale visit order) move rows
without any code changing.

Measurement-regime boundaries are respected, because ignoring them produces nonsense:
  - DEVICE columns are only comparable from the gcsample repair onward (AMD 2026-08-07 db7e6dd8,
    CUDA 2026-08-09 d5f6814a); before it every device row timed the collector (finding (s)).
  - CPU columns were never affected by gcsample, but the decision-38/39 threading rewrite
    (2026-07-22) reshaped them, so that is their floor.
A cell is only compared against readings inside its own regime.
"""
import os, re, subprocess, sys, statistics
from collections import defaultdict

# Derived from this file's own location, not hardcoded: `report.jl` invokes the script from
# whatever directory a sweep happens to run in, and the fleet's two hosts need not agree on
# an absolute path. A wrong REPO here would not error — `git show` would simply find nothing,
# and the scan would report a clean history it never read.
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def sh(*a):
    return subprocess.run(a, cwd=REPO, capture_output=True, text=True).stdout

def parse(text):
    """(operation, workload, column) -> ms, from one RESULTS.md."""
    out, hdr = {}, None
    for line in text.splitlines():
        if line.startswith("| operation"):
            hdr = [x.strip() for x in line.strip().strip("|").split("|")]
            continue
        if not line.startswith("|") or hdr is None:
            continue
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(c) != len(hdr) or c[0].startswith("---"):
            continue
        for col, cell in zip(hdr[2:], c[2:]):
            m = re.match(r"([\d.]+)\s*(ms|μs|us|s)$", cell)
            if m:
                v = float(m.group(1)) * {"s": 1000, "ms": 1, "μs": 1e-3, "us": 1e-3}[m.group(2)]
                out[(c[0], c[1], col)] = v
    return out

commits = []
for line in sh("git", "log", "--format=%h %ad", "--date=short", "--reverse",
               "--", "benchmark/RESULTS.md").splitlines():
    h, d = line.split()
    commits.append((h, d))

CPU_FLOOR, AMD_FLOOR, NV_FLOOR = "2026-07-22", "2026-08-07", "2026-08-09"
def floor_for(col):
    if col.startswith("CPU"):  return CPU_FLOOR
    if "7900" in col or "6700" in col: return AMD_FLOOR
    return NV_FLOOR

series = defaultdict(list)          # key -> [(date, commit, ms)]
for h, d in commits:
    tbl = parse(sh("git", "show", f"{h}:benchmark/RESULTS.md"))
    for k, v in tbl.items():
        if d >= floor_for(k[2]):
            series[k].append((d, h, v))

head = {k: v[-1] for k, v in series.items() if v}
print(f"parsed {len(commits)} versions of RESULTS.md; {len(series)} (row, column) cells in-regime\n")

THRESHOLD = float(sys.argv[1]) if len(sys.argv) > 1 else 1.25
findings = []
for k, hist in series.items():
    if len(hist) < 2:
        continue
    op, wl, col = k
    cur_date, cur_h, cur = hist[-1]
    best_v, best_d, best_h = min(((v, d, h) for d, h, v in hist[:-1]))
    if cur / best_v >= THRESHOLD:
        # Persistence: is HEAD's regime the tail, or is the old best a one-off dip?
        tail = [v for _, _, v in hist[-3:]]
        pre = [v for _, _, v in hist[:-3]] or [best_v]
        findings.append({
            "op": op, "wl": wl, "col": col, "ratio": cur / best_v,
            "best": best_v, "best_date": best_d, "cur": cur, "cur_date": cur_date,
            "n": len(hist), "tail_med": statistics.median(tail), "pre_med": statistics.median(pre),
        })

findings.sort(key=lambda f: -f["ratio"])
print(f"=== cells at least {THRESHOLD:.2f}x slower at HEAD than their in-regime best: {len(findings)}\n")
for f in findings[:45]:
    persistent = "PERSISTENT" if f["tail_med"] / f["pre_med"] >= 1.15 else "one-off?"
    print(f"{f['ratio']:6.2f}x  {f['op'][:34]:34s} {f['wl'][:16]:16s} {f['col']:15s} "
          f"{f['best']:9.3f}({f['best_date'][5:]}) -> {f['cur']:9.3f}  n={f['n']:2d}  {persistent}")

# Which operations are hit across MANY columns? A real code regression usually is.
by_op = defaultdict(set)
for f in findings:
    by_op[f["op"]].add(f["col"])
print("\n=== operations flagged in 3+ columns (a code regression usually crosses columns):")
for op, cols in sorted(by_op.items(), key=lambda x: -len(x[1])):
    if len(cols) >= 3:
        print(f"  {len(cols):2d} columns  {op}")
