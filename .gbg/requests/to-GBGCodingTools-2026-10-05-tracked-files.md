Status: open — approved by the owner on 2026-10-05; sent to the GBGCodingTools session the same day.

# To GBGCodingTools: what a package's git may hold, fleet-wide

The owner wants this never to happen again in any GBG package: PF's repository was found holding
session drafts and working notes as if they were package files — a multi-GPU design proposal (14
files), notes to other sessions, a triage note, the session work queue, old review-round piles, the
pre-tool instruments, and a per-machine settings file. They were committed because git was the
easiest way to carry a note between machines; nothing said no, and nothing checked. A public release
would have published all of it.

## What is asked

1. **The tracked-path rule.** A package's git holds only:
   - package source (`src/`, `ext/`, `Project.toml`, `README`, `LICENSE`, `.gitignore`);
   - tests (`test/`, the GPU and survey environments included);
   - docs (`docs/`, not the generated build);
   - examples (`examples/`);
   - benchmarks (`benchmark/`, with their committed results and per-host baselines);
   - `CLAUDE.md`;
   - `.github/` (CI and the docs deployment);
   - the tool's own files: `.gbg/config.jl`, `.gbg/policy/`, `.claude/settings.json`,
     `.claude/hooks/`, `.claude/skills/`, and the records the tool keeps for the owner
     (`.gbg/questions.json`, closed runs under `.gbg/runs/`) — the owner ruled these stay, being
     made by the tool and described centrally by it.

   Everything else is reported by `gbg check`. A package needing an exception declares it as a
   switch with its reason, like any other rule.

2. **`inspiration/` as the one home for drafts and session notes.** It already exists in the
   packages, git ignores it, and since the repositories live in Dropbox it reaches both machines. The
   rulebook should name it, so a session never needs git to carry a note between hosts — the cause
   of the mess.

3. **A non-blocking notice of every newly tracked file.** The end-of-turn hook lists each file a
   session added to git that turn, shown in the chat as a warning ("added: `docs/foo.md`"). It blocks
   nothing; it makes a new tracked file never silent.

## Considered and not asked

A reachability check (every tracked file under an allowed directory must be reached from an entry
point, so an orphaned draft in `docs/` or `test/` is reported) was discussed and declined for now: a
draft wired in on purpose has become documentation or a test by intent, and is visible on the
rendered site or in every test run anyway.

## PF's own cleanup

PF will clean its repository against the rule once it exists, on the owner's rulings, the 84
pre-tool instrument files from your earlier message included.
