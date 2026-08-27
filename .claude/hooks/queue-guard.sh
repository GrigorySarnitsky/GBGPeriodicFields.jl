#!/usr/bin/env bash
# STOP HOOK — refuses to let the session end while committed work is open.
#
# WHY THIS EXISTS. Told "continue with everything, don't stop in the middle", the session finished
# three of five queued items and then reported status with the remaining two labelled "remaining
# queue, in order". Stopping to narrate IS stopping. Every previous defence against this was a
# sentence in CLAUDE.md, and this session has now measured, repeatedly, that a rule written down
# reads as compliance while nothing checks it. So the check is not a rule: the environment refuses
# the stop.
#
# CONTRACT. `.claude/WORK_QUEUE.md` holds one line per item, `- [ ]` open, `- [x]` done. While any
# item is open this exits 2, which Claude Code treats as "do not stop", feeding stderr back as the
# reason. Closing an item is an edit that shows in the diff, so the queue cannot be silently emptied.
#
# THE LOOP GUARD IS LOAD-BEARING. `stop_hook_active` is true when the session is already being held
# open by this hook; blocking again there would trap the session forever with no way out. It is the
# difference between a harness and a cage.
set -uo pipefail
payload=$(cat)
if grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$payload"; then
  exit 0
fi

queue="${CLAUDE_PROJECT_DIR:-.}/.claude/WORK_QUEUE.md"
[[ -f "$queue" ]] || exit 0

open_items=$(grep -nE '^[[:space:]]*- \[ \]' "$queue" || true)
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
