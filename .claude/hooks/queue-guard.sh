#!/usr/bin/env bash
# STOP HOOK — refuses to let the session end while committed work is open.
# Written by GBGCodingTools v2.0.0-rc.7; do not edit.
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
# THE UNCOUNTED HEADING. Lines under "## From the last review" are NOT counted, up to the next
# heading: a run's leftovers are the owner's list to act on when he chooses, and holding a session to
# them would be a review setting a session to work nobody asked for. A section the owner adds below
# it is his, and counted.
set -uo pipefail
payload=$(cat)
if grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$payload"; then
  exit 0
fi

queue="${CLAUDE_PROJECT_DIR:-.}/.claude/WORK_QUEUE.md"
[[ -f "$queue" ]] || exit 0

counted=$(awk '/^## From the last review/{skip=1; next} /^## /{skip=0} !skip' "$queue")
open_items=$(grep -nE '^[[:space:]]*- \[ \]' <<<"$counted" || true)
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
