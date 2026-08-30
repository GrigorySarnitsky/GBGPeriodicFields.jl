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

- [x] Mechanism prototype: coverage → method spans, validated on a decisive called/uncalled pair
- [x] Build the per-method ledger: 575 cells, 572 covered, 3 closed with reasons, 0 UNCOVERED
- [x] Falsify the ledger: five probes, all passing, targets taken from a perturbed copy
- [x] Wired into runtests and the exit code; three defects in the ledger itself found and fixed
- [x] The design's predicted violation: found as the names(mod) enumeration gap, 107 cells suppressed
- [x] Uncovered driven 386 → 0 across eight sweeps; ref_divergence and ref_radial_correlation widened
- [x] Full survey re-run 2026-08-29, exit code CAPTURED = 2 (the known radial_spectrum tie-break; every asserting lane clean)
- [x] DESIGN.md, CLAUDE.md, TESTING.md updated; committed and pushed

## Open (authorised 2026-08-29: close survey item 4, the two operations with no buildable call)

- [x] `displace!`: term-pair pool entry added; its four methods now get the universal checks
- [x] `adapt`: reported as not-defined-here, covered through its hook, not as a gap
- [x] Measured: "every public operation is reached by the invocation engine"; invocations 3,416,256 → 3,417,216
- [x] Full survey re-run, SURVEY_EXIT_CODE=2 captured (the known radial_spectrum cells); committed

## Open (authorised 2026-08-29: retire result_type from the applicability ledger)

- [x] Removed `:result_type` from APPLICABILITY and from the classifier
- [x] Measured on a full run: applicable 1086 → 966 (−120), unasserted 378 → 283 (−95), every other lane byte-identical
- [x] Survey re-run, SURVEY_EXIT_CODE=2 captured; committed and pushed

## Open (authorised 2026-08-29: ENFORCE the un-guarded promise kinds)

- [x] peer_rejections.jl: derived denominator, falsified 3 arms — and it FOUND inner accepting cross-domain pairs
- [x] All 52 closed: 29 invocations + cited exemptions; inner FIXED; wrap!/displace!/copyto! first-asserted
- [x] absence_gate.jl: all 38 asymmetric operations refuse their absent side; falsified both ways
- [x] Decided: survey-enforced by derived lanes; no redundant gates; recorded in CLAUDE.md
- [x] Both gates falsified by perturbation before being trusted
- [x] Pkg.test() 130 testsets green; survey SURVEY_EXIT_CODE=2 (the known 72), relations lane green after its fixture fix

## Open (2026-08-29: IT's CPU performance report — verify, fix the bug-grade one, present the rest)

- [x] VERIFIED: 70x at -t8 on the 9800X3D (14.7 ms flat across thread counts): weighted_inner CPU vs inner, same size, and read the code path
- [x] FIXED: fixed-tree over axis-1 columns; 33x at t8, 21x tuple; decision-72 bitwise held; invariance asserted through the fixed-tree path, single and tuple forms,
- [x] Micro-measured; CUDA suite 432/432 over the byte-identical GPU branch (not the benchmark suite — that stays consent-gated); GPU parity run
- [x] Findings 2 and 3 recorded below as planned items with IT's evidence; record with measurements as planned items, no fixes unasked
- [x] Replied, committed, pushed

## Open (2026-08-30, user-directed: accelerate the point transfer — research, build, MEASURE)

Target: 256^3 grid, 1,000,000 points, BOTH backends (CPU + CUDA here; ROCm needs Aiporetne).
Everything opt-in behind options — techniques help or hurt by setup, so measure, never assume.

- [x] RESEARCH: three lanes (ordering/sort, GPU kernel+memory, CPU) — findings acted on or recorded
      blocking, memory layout, scatter strategy, batching, precision, occupancy)
- [x] BASELINE measured both backends, both element types, R=0/1, four grid/point combinations
- [x] Shipped: transfer_order + `order` on all EIGHT entry points (opt-in), and the wrap walk (bit-identical)
- [x] MEASURED across the full product; three candidates measured and REJECTED (Morton, bucket stability, static unroll)
- [x] Bitwise gather invariance (and under a reversed order), GPU parity 448, Pkg.test 134, allocation pins
- [x] Docs: decision 78, findings (ad)/(ae)/(af), TESTING axis, CLAUDE.md, API page — two roadmap items closed
- [x] Committed and pushed (a017dfe4, 48d06122, 3a89c67f, bed3c997, ca7e7143)

## Open (2026-08-30, user question: was the SCHEME varied, and did we reach 512^3?)

Honest answer: no on both. Every perf number was CatmullRom (4 nodes/axis) at <= 256^3.
Stencil width spans 2..8 nodes/axis across the schemes = 8..512 nodes/point.

- [x] Swept 2/4/6/8 nodes per axis, both backends: ordering payoff RISES with width (to 6.95x CPU); wrap walk REGRESSES 14% at width 8 with a fibre
      Lagrange(3) (8) — visit-order payoff AND wrap-walk payoff per scheme, both backends
- [x] Reached 1024^3 on device (8 GiB of fields) and 512^3 on CPU
- [x] Prediction CONFIRMED: the walk hits the same failure as the ntuple hoist at width 8; hybrid measured and strictly worse; kept with the corner documented
- [x] Finding (ad), decision 78 and CLAUDE.md corrected (not appended to)
- [x] Committed and pushed (86101f93)

## Open (2026-08-30: adversarial review of decision 78 found REAL defects — fix them)

- [x] FIXED: TransferOrder carries the bijection, validated once at construction; bare vectors refused
- [x] FIXED: Int64 keys throughout
- [x] FIXED: _tile_index compares in floating point before converting
- [x] FIXED: element-type refusal (invariant 14)
- [x] FIXED: both corrected, and the grid-scaling scratch priced
- [x] FIXED: ranges accepted and materialised
- [x] Witnesses promoted into test/transfer_order.jl, plus the index-equivalence proof the suite lacked
- [x] Pkg.test 137, CUDA 454, docs green; committed and pushed (097c3c23, 04923f79)

## Open (2026-08-30, user-directed: the born-slow triage, wired into the post-benchmark analyzer)

- [x] triage.jl built: every-host flatness + declared docstring-cost peers; class-median tried and dropped as noise
- [x] Wired into report.jl; standalone entry kept
- [x] Run: 46 flat (43 known; weighted_inner retro-flags at 0.99x) + 91 peer (all known) + ONE genuine discovery: radial shell binning flat on both hosts
- [x] triage_selftest: flags a flattened scaler, spares a true one, retro-flags the known pair
- [x] Regenerated; all ten columns bit-for-bit identical, triage section appended
- [x] Finding (ag); the new radial-binning investigate item in CLAUDE.md; committed

## Open (2026-08-30, user-directed: IT item 2 — hoist the fiber-constant exp)

Constraint from the user: NO performance or allocation regression anywhere. So: R=0 route untouched;
bitwise identity proven against the committed code; A/B on both backends across sizes/threads BEFORE
committing; allocation pins stay at zero; if any measured cell regresses, that cell keeps its old route.

- [x] Read: 4 broadcast helpers, 6 public arities
- [x] Implemented: kernel pair, exp once per mode; serial bufferless (zero-pin), threaded row-buffered with the factor fill fused into the first component
- [x] BITWISE IDENTICAL, 126 cells; plus the complex-ŵ case the fixtures missed (buffer type fixed)
- [x] A/B'd: t1 2.4-3.9x, t4 1.65x, device 1.3-2.1x F64; residuals DISCLOSED (F64 256^3-t8 +3-6%, device F32 comb -2%); 512^3-t8 even
      cell keeps the broadcast
- [x] Guards: toggle bitwise (two real bodies), pair guard extended to Convolution (found 3 pre-existing unguarded pairs, 12->17), holder retired at ideal, parity 83->105 with reasons
- [x] Decision 79, finding (ah), CLAUDE item 2 closed; convolution tiny-grid gate 18/18
- [x] Pkg.test 137 green, CUDA 454 green; committed and pushed

## Open (2026-08-30, user-directed: IT item 3, option 3 — the standalone prototype, NO src changes)

- [x] Prototype run: pkg vs hand vs @simd, cross + mul!, 36 cells
- [x] Bitwise: every variant == the package in every cell
- [x] Measured t1/t4/t8 x 128/256/512 x F64/F32 with GB/s: t1 wins 1.16-3.58x; t4/t8 out-of-cache AT THE ROOF (43-47 GB/s both arms)
- [x] Verdict: option 2 DEAD (simd==plain everywhere); option 1 regime-bound here, trigger = the 12700K measurement; recorded in CLAUDE.md

## Open (2026-08-30, user-directed: transfer_order argument order + the tile_size question)

- [x] Swapped to transfer_order(grid, points; ...) — the transfer-family order
- [x] All call sites updated (a regex over-match into _check_transfer_order caught and repaired; the parenthesised sites hand-fixed)
- [x] Measured both backends x widths 4/8: the optimum tracks the BACKEND, not the scheme
- [x] tile_size KEPT on the data; keyword/positional policy codified in CLAUDE.md §Style
- [x] 137 + 454 + docs green; the gate caught a benchmark row broken since TransferOrder landed (fixed)

