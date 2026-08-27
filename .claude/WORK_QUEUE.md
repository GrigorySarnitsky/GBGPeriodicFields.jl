# Session work queue

One line per committed item. `- [ ]` open, `- [x]` done. `.claude/hooks/queue-guard.sh` is a Stop
hook that refuses to let the session end while any item is open, so "am I finished?" is answered by
a program rather than by my judgement — which this session measured as unreliable in exactly the
flattering direction.

Close an item ONLY when it is done and verified. An item closed to end the turn is the defect the
hook exists to prevent. A genuinely blocked item is closed with the blocker written on the line, so
the block shows in the diff instead of being silent.

## Open (authorised 2026-08-27: "continue with everything, don't stop in the middle")

- [ ] Exhaustive survey: run to completion, read the result, ANALYSE it (not just report the exit code)
- [ ] Benchmarks: transfer + convolution classes on an IDLE machine (the NUFFT fix adds a runtime
      comparison per axis per point, so the transfer class genuinely moved)
- [ ] RESULTS.md: regenerate over all archives, diff against the previous archive, explain every
      systematic movement before naming a cause
- [ ] CLAUDE.md: replace the stale survey figures (111 of 113 oracles, 3.4M invocations) with the
      numbers this run actually measures
- [ ] Commit and push everything, including this harness
