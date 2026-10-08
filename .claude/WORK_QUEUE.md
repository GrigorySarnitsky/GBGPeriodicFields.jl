# Session work queue

What is still to do, one line per item: `- [ ]` and the item. `.claude/hooks/queue-guard.sh` holds a
session at the end of a turn while an item is open, so "am I finished?" is answered by a program.

A finished item is deleted in the commit that finishes it; git keeps the history. A blocked item stays
open and begins `BLOCKED:` with its reason.

## Code the owner asked for
