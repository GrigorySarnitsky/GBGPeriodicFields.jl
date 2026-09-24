#!/usr/bin/env bash
# STOP HOOK — refuses to let the session end while committed work is open.
# Written by GBGCodingTools v2.0.0-rc.23; do not edit.
#
# CONTRACT. `.claude/WORK_QUEUE.md` holds one line per item, `- [ ]` open, `- [x]` done. While any
# item is open this exits 2, which Claude Code treats as "do not stop", feeding stderr back as the
# reason. Closing an item is an edit that shows in the diff, so the queue cannot be silently emptied.
#
# WHY IT IS A HOOK AND NOT A RULE. Told "continue with everything, don't stop in the middle", a
# session finished three of five queued items and reported status with the other two labelled
# "remaining queue". Stopping to narrate IS stopping. Every earlier defence was a sentence in
# CLAUDE.md, and a rule written down reads as compliance while nothing checks it.
#
# THE LOOP GUARD IS LOAD-BEARING. `stop_hook_active` is true when the session is already being held
# open by this hook; blocking again there would trap it forever. It is the difference between a
# harness and a cage.
#
# AN OPEN RUN HOLDS THE SESSION TOO, and for the reason this hook exists at all: a run is walked
# stage by stage BY THE SESSION — Julia cannot launch an agent — so a session that stops in the middle
# has spent its agents for nothing and left a run that blocks the next one. The queue cannot catch
# that, because a run writes its queue lines at CLOSE, which is the point it has not reached. Found
# when the first real review stopped between stages to report (GBGPeriodicFields, 2026-09-22).
#
# ABANDONING IS NOT THE WAY OUT and is not offered as one: it DROPS the findings. A session that
# cannot go on leaves the run OPEN and says where it stands; the next session continues it, and a
# stage whose agents already answered is not relaunched. Abandoning is the owner's call, for a run he
# does not want continued.
#
# THE UNCOUNTED HEADINGS. Lines under "## From the last review", and under "## Code the owner asked
# for" — his list of code to change, which no session is held to — are NOT counted, up to the next
# heading: a run's leftovers are the owner's list to act on when he chooses, and holding a session to
# them would be a review setting a session to work nobody asked for. A section the owner adds below
# it is his, and counted.
set -uo pipefail
payload=$(cat)
if grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$payload"; then
  exit 0
fi

runs="${CLAUDE_PROJECT_DIR:-.}/.gbg/runs"
if [[ -d "$runs" ]]; then
  for d in "$runs"/*/; do
    [[ -f "$d/stage" && ! -f "$d/run.json" ]] || continue
    id=$(basename "$d")
    {
      echo "A RUN IS OPEN — $id, at stage $(cat "$d/stage" 2>/dev/null || echo '?')."
      echo
      echo "A run is walked stage by stage by YOU: the verb writes each stage's arguments and exits,"
      echo "because Julia cannot launch an agent. Stopping in the middle spends its agents for nothing"
      echo "and leaves a run that blocks the next one."
      echo
      echo "  Continue it:  gbg run next   (or collect, or close — whichever it is waiting for)"
      echo "  Or stop here: leave it OPEN and say which run and which stage, so the next session"
      echo "                picks it up. Nothing is lost; a stage whose agents answered is not relaunched."
      echo
      echo "Do NOT abandon it to end the turn: 'gbg run abandon' DROPS its findings. That is the"
      echo "owner's call, for a run he does not want continued."
    } >&2
    exit 2
  done
fi

queue="${CLAUDE_PROJECT_DIR:-.}/.claude/WORK_QUEUE.md"
[[ -f "$queue" ]] || exit 0

# The leftovers section is the EXACT heading line, up to the next heading of ANY level, and the
# lines printed carry their number in the file (found in review, 2026-09-23: a section of the
# owner's under a `#` heading, or one whose name began with the leftovers', went uncounted).
open_items=$(awk '{ h = $0; sub(/[ 	]+$/, "", h) }
                    h == "## From the last review" || h == "## Code the owner asked for" {skip=1; next}
                    /^#/ {skip=0}
                    !skip && /^[[:space:]]*- \[ \]/ {print NR ":" $0}' "$queue")
[[ -z "$open_items" ]] && exit 0

{
  echo "WORK QUEUE IS NOT EMPTY — you committed to finishing these before reporting back:"
  echo
  sed 's/^/  /' <<<"$open_items"
  echo
  echo "Continue working. Close each item in .claude/WORK_QUEUE.md by changing '- [ ]' to '- [x]'"
  echo "ONLY when it is actually done and verified — an item closed to end the turn is the defect"
  echo "this hook exists to prevent. If an item is genuinely blocked, mark it '- [x]' and record the"
  echo "blocker on the same line, so the block is visible in the diff rather than silent."
} >&2
exit 2
