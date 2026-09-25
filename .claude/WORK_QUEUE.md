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
- [x] Shipped: point_traversal_order + `order` on all EIGHT entry points (opt-in), and the wrap walk (bit-identical)
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

- [x] FIXED: PointTraversalOrder carries the bijection, validated once at construction; bare vectors refused
- [x] FIXED: Int64 keys throughout
- [x] FIXED: _tile_index compares in floating point before converting
- [x] FIXED: element-type refusal (invariant 14)
- [x] FIXED: both corrected, and the grid-scaling scratch priced
- [x] FIXED: ranges accepted and materialised
- [x] Witnesses promoted into test/point_traversal_order.jl, plus the index-equivalence proof the suite lacked
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

## Open (2026-08-30, user-directed: point_traversal_order argument order + the tile_size question)

- [x] Swapped to point_traversal_order(grid, points; ...) — the transfer-family order
- [x] All call sites updated (a regex over-match into _check_point_traversal_order caught and repaired; the parenthesised sites hand-fixed)
- [x] Measured both backends x widths 4/8: the optimum tracks the BACKEND, not the scheme
- [x] tile_size KEPT on the data; keyword/positional policy codified in CLAUDE.md §Style
- [x] 137 + 454 + docs green; the gate caught a benchmark row broken since PointTraversalOrder landed (fixed)

## Open (2026-08-31, user-granted: THE BENCHMARK SESSION — the box is mine, run to completion)

- [x] Box idle (load 0.00); all 21 archives backed up first
- [x] CUDA lane swept: median 0.987, movers = decisions 78/79 + the alpha-association fix only
- [x] t1/t2/t4 swept: medians 1.000/0.999/1.000; weighted_inner 7.7x/14x/30x
- [x] t8 split-swept TWICE: the first merge threw and an unconditional rm destroyed the parts (recorded in finding (ai)); re-swept into scratchpad, merged verified both directions (760 rows), benchmark/merge_parts.jl committed as the tool
- [x] Every lane diffed and every mover explained; two micro-second cells noted as §4(u) jitter
- [x] Canaries green x3; baselines refrozen (improvements refreeze too — a stale slow baseline hides the next regression)
- [x] RESULTS.md over all ten; triage A 46->23 (only the radial-binning discovery unexplained, CONFIRMED on fresh lanes), B 91->33 all known/stale-host; the scalar exponential peer pair corrected to a non-declaration
- [x] Finding (ai); committed and pushed


## Open (2026-09-22: HT asks for a width-parameterized top-hat window; owner deferred it behind the CT work)

- [x] DEFERRED by the owner — evaluated, not built. HT wants the generalization of `assignment_window`
      from the grid spacing to an arbitrary width, for a k(l)/ε(l) sub-box diagnostic. VERDICT: the
      request is sound and the object belongs here. `assignment_window` IS W(Δ)² — `src/Convolution.jl:1856`
      computes sinc²(|k_a|Δ_a/2) per axis — so the generalization is that body with `spacing[a]` replaced
      by a width. `SeparableKernel` has no public constructor (`:280`, `:466`), so HT genuinely cannot
      build it and the raise is correct. Both their assumptions hold: the tuple form takes
      `Tuple{Vararg{SpectralKernel}}` so a `ProductKernel` type-checks, and `test/reductions.jl:347,787`
      already exercise `convolve(radial, separable)` as a weight, both factors real so the real-weight
      check passes. SHAPE: return W, not W² — W is the primitive that acts on the field, W² is its
      autoconvolution and separable kernels already compose for free (decision 50), so shipping both
      would be invariant 1's "for completeness"; HT squares it themselves. Then `assignment_window`
      becomes `convolve(w, w)`, which is DRY and gives a bitwise consistency oracle. Name: NOT
      `box_window` (this package says "the box" for the domain throughout) — `tophat_window(multipliers,
      width)`, width positional since it changes the result, accepting a scalar or a per-axis triple as
      `translation_kernel` takes its offset. FLAGS FOR HT: their b ≈ 16 batch model omits register
      pressure, which finding (aq) measured halving occupancy on gfx1100, and a 16-wide tuple
      accumulator over 16 nested `ProductKernel` broadcasts is that shape — no ceiling is documented, so
      sweep b rather than assume, and expect the device optimum below their 12–16; nested `Broadcasted`
      is also the known-fragile spot on AMDGPU (the reason `_kernel_data` calls `instantiate`), so check
      ROCm before committing to a batch size. The cubic case cannot collapse like the spherical one —
      W² is not a function of |κ| — so their batching is the right structure and there is no cheaper
      route. Pin l = L (W picks out the mean alone, k(L) = k for a zero-mean field) and l → 0 (W ≡ 1,
      k(0) = 0) as tests; Nyquist is already right, the window using the TRUE |k| so it stays real and
      even. Full definition of done applies if it is built.

## Code the owner asked for

- [x] 2026-09-24-documentation-review-01-006 Module docstrings are not maps. Several carry formulas that belong in the operation homes (RULE.DOC.TWO_TIER too), and two put a glossary or an admonition between the identity and the contents list, where the order should be identity, list, then an optional trailing remark. — Done on the owner's ruling, 2026-09-25/26: commit(s) cd315fbf, 8caadf3c.
- [x] 2026-09-24-documentation-review-01-009 Some keyword arguments change the result, and no Switch in .gbg/config.jl covers them. The corrected keyword of var/std/cov changes the returned number. The array_type keyword of the function-initialized field constructors picks the storage family, which the family constructors take positionally. Grid3D's origin keyword and the callable field's scheme keyword are owner-settled exceptions in CLAUDE.md, but they are not declared as Switches either, which is the only form of exception the rule recognizes. — Done on the owner's ruling, 2026-09-25/26: commit(s) 19826de8.
- [x] 2026-09-24-documentation-review-01-010 Some docstrings use symbols that the notation page assigns elsewhere. They index grid and point sums with n and i where the page fixes sum_x over grid points and sum_p (f_p) over points, i being a fiber index. They write the base average as \bar f where the page fixes <f>. translation_kernel writes the derivative wavenumber as \tilde k_a where the page names it a. weighted_inner uses w both as the mode multiplier and as a physical convolution kernel (w ⋆ g). The architecture document calls the field s where the page's symbol is f. — Done on the owner's ruling, 2026-09-25/26: commit(s) f85c346a.
- [x] 2026-09-24-documentation-review-01-011 The radial_spectrum docstring is off by one against the code. It says spectrum[i] holds the modes with round(|k|/Δk) = i, but the returned vectors are 1-based: spectrum[1] is the κ = 0 shell, and in general spectrum[i] holds round(|k|/Δk) = i - 1. — Done on the owner's ruling, 2026-09-25/26: commit(s) f1e87e8a.
- [x] 2026-09-24-documentation-review-01-016 Rendered code blocks that scroll sideways on a desktop page: each has one or more lines of 95-114 characters, while the 816 px column holds about 90 (about 87 inside a docstring). Measured natural widths are 826-986 px against boxes of 756-812 px. — Done on the owner's ruling, 2026-09-25/26: commit(s) 8bd71d78.
- [x] 2026-09-24-documentation-review-01-017 Display formulas set several equations side by side on one rendered line behind \quad/\qquad, which the rule forbids by name. They fit at desktop width today, but they are the packed form the rule exists to prevent. — Done on the owner's ruling, 2026-09-25/26: commit(s) 42d70de2, aca97e2f.
- [x] 2026-09-24-documentation-review-01-018 Display formulas were wrapped in the source by a bare line break, with no aligned or gathered environment. KaTeX reads a newline as a space, so each one renders as a single long line and the wrap the author wrote is lost. In the reality_projection! docstring, two separate assignments merge into one line. They fit the desktop column now; they do not fit narrower screens. — Done on the owner's ruling, 2026-09-25/26: commit(s) e7d60b5a, 8e46fbf6.
- [x] 2026-09-24-documentation-review-01-095 Command-line flags are set in backtick spans although they are not well-formed Julia (a leading '--' does not parse); the rule admits only Julia in a code span. Possibly accepted practice for CLI flags, hence flagged as uncertain. — Done on the owner's ruling, 2026-09-25/26: commit(s) 6205ad31.
