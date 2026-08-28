# Session work queue

One line per committed item. `- [ ]` open, `- [x]` done. `.claude/hooks/queue-guard.sh` is a Stop
hook that refuses to let the session end while any item is open, so "am I finished?" is answered by
a program rather than by my judgement — which this session measured as unreliable in exactly the
flattering direction.

Close an item ONLY when it is done and verified. An item closed to end the turn is the defect the
hook exists to prevent. A genuinely blocked item is closed with the blocker written on the line, so
the block shows in the diff instead of being silent.

## Open (authorised 2026-08-27: "continue with everything, don't stop in the middle")

- [x] Exhaustive survey: RUN (66 min), analysed — 0 correctness findings; its one real finding (576 type-stability cells, all `reality_residual` inferring `Any`) is FIXED
- [x] Benchmarks: transfer + convolution re-swept on CPU t1, CPU t4 and GPU 5070TI, idle machine
      comparison per axis per point, so the transfer class genuinely moved)
- [x] RESULTS.md: regenerated over the correct ten archives, merge verified both directions, analysed as finding (ab)
      systematic movement before naming a cause
- [x] CLAUDE.md: survey figures replaced with the 2026-08-28 run's measured numbers
- [x] Commit and push everything, including this harness

## Open (authorised 2026-08-28: "find out the reason for all of the slowdowns. And I mean all")

- [x] CPU t1: five 512³ convolution rows, x1.16–1.35 — isolate CODE from ENVIRONMENT by measuring the
      baseline commit in the same sweep shape
- [x] CPU t4: five 128³/256³ rows (convolve! scalar, ∘radial, and three spline interpolate rows), same method
- [x] GPU 5070TI: ten small-grid transfer rows, x1.13–1.49, same method against its own baseline commit
- [x] Attribute each cluster to a named cause, or state precisely what was excluded and what remains
- [x] Record the findings and commit

## Open (authorised 2026-08-28: "Implement now inverse curl")

- [x] `inverse_curl!`/`inverse_curl` — one-pass KA kernel + gated CPU twin
- [x] CPU correctness against the closed-form pair, round trip, gauge, zero mode, aliasing
- [x] GPU parity 432/432; bitwise thread-invariance + decision-47 probe green
- [x] allocations zero row, pass_audit row, oracle_registry entry, survey value rows (121/121)
- [x] benchmark row added; tiny-grid gate 88/88
- [x] docs: decision 77, FORMALIZATION entry, TESTING, API page, CLAUDE.md; four baselines refrozen
- [x] Pkg.test() 126 testsets green, CUDA green, docs green

## Open (authorised 2026-08-28: "Finish the ledger and do not stop, until you are done")

- [ ] Mechanism prototype: map executed code back to METHODS, derived, not hand-maintained
- [ ] Build the per-method ledger: every (operation × method) cell covered by a value row, closed by a
      recorded reason, or reported UNCOVERED — and the ledger FAILS on the third
- [ ] Falsify the ledger by PERTURBATION, all four probes, in selfcheck.jl (it is the measuring
      instrument; a defect in it reports coverage nobody investigates)
- [ ] Wire into runtests.jl and the exit code; audit the ledger's own mechanics before trusting a number
- [ ] Identify the ONE violation DESIGN.md says the corrected instrument surfaces
- [ ] Work the uncovered count down: widen the non-generic references, drive the generic ones at more
      than one value
- [ ] Re-run the full survey (it is stale: reality_residual fix + inverse_curl unseen), capture the
      EXIT CODE this time
- [ ] Update DESIGN.md (resumption point closed), CLAUDE.md, TESTING.md; commit and push

