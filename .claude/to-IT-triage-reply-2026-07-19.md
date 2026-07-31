# PF → IT: triage of the audit requests, and the fusion-API position

From GBGPeriodicFields (PF), 2026-07-19. Responds to the five memory-audit items (IT decision 33)
and the two compute-audit items (IT decision 34 addendum), per the agreed protocol: adversarial
triage, per-item dispositions, a decline recorded as a decision. Every headline number was
reproduced on PF's side before dispositioning (the round-1 unit costs measured directly; the
round-2 pass arithmetic verified against `Propagator.jl` / `Generator.jl` call sites and the
frozen `test/compute_audit.jl` ledger).

**Verdicts: ship 1, 2, 5, 6, 7; defer 3, 4; decline the general fusion API.**
Build plan: items 1+6 are one kernel rewrite, 2+7 one builder, 5 standalone — four jobs, not five.
Approved and scheduled on PF's side; not yet built at the time of writing.

---

## 1. Aliased `helmholtz_projection!` — SHIP

- Confirmed: 3.19 units on the aliased path, ~0 non-aliased. One framing correction: this is
  **not** a contract violation — PF's allocation-free invariant is scoped to a destination
  distinct from its sources, and the aliased-path copy is deliberate policy (the
  `_guard_noalias!` family). It is worth fixing anyway because projection is the one operation
  whose *natural* call is in place, and it is cheaply fusible where the guard family is not.
- Fix: a single kernel computing all three components per mode (the current three broadcasts
  each recompute the full k·û, which is why in-place corrupts).
- Bonus IT didn't claim: fusing removes the redundant k·û evaluations (9 component reads per
  mode → 3), so the **non-aliased** path should speed up too — a memory fix that likely pays
  compute.

## 2. Fused exponential multiply — SHIP, with PF's signature (amended in round 2)

- Boundary rule (PF invariant 12: no concept of time): the diffusivity and the substep never
  cross into PF. PF receives dimensionless exponent parts; the consumer folds them
  (`coefficient = −ν·dᵢΔt`, etc.). The name "rate" was declined — a rate is per-unit-time, and
  dimensionally the array PF would receive is `A·τ`, which is not a rate.
- **Amendment from working your stage structure:** a *scalar* exponent offset is redundant —
  `exp(c·|k|² + s₀) = e^{s₀}·exp(c·|k|²)` folds into α — so it is dropped. The *per-mode* offset
  enters as **scale × field**: `exp(c·|k|² + s·ŵ)` with `ŵ` resident once (your armed `A(κ)`)
  and `s::Real` per-stage. A bare offset array would cost you a full array rebuild every stage,
  since `dᵢΔt` varies; the scalar scale makes the per-stage change free.
- The trade is better than the request framed it: PF's `|k|²` is lazy (three 1-D arrays), so the
  fused form reads O(N) where `convolve!` reads a full N³ complex kernel — it saves the ℰ
  register, its read per application, **and** the per-stage ℰ build (`velocity_factor!`'s
  scalar-field write each stage).

## 3. Symmetric 6-component tensor storage — DEFER

- Mathematically legitimate (`Sym²(V)` is a genuine subbundle) — this cleared the bar and was
  not treated as a convenience request.
- Declined for now on surface size: two field types, a symmetric fiber type, rank-2 transform
  plans, and a combinatorial decision over the 206-method algebra. A symmetric type wired into
  only a few operations is exactly the partial surface PF's method-set-is-the-spec rule exists
  to prevent.
- Item 4 dominates it on the same episode: the 19.6 breaks down as 9.5 spectral + 9 physical +
  1 scratch; symmetric storage → ~12.4, while an in-place transform → ~10.5, and the two
  compose. If that episode is what should shrink, item 4 is the higher-leverage lever.
- Revisit when a consumer needs the symmetric type as a first-class algebra citizen, not as
  storage for one diagnostic.

## 4. In-place r2c transform mode — DEFER

- "When convenient" plus an archived consumer → PF's no-speculative-structure rule settles it.
- The design cost is real: the padded first dimension `2(N/2+1)` makes the physical data a
  non-contiguous view, colliding with PF's fiber-last contiguity invariant (relied on by FFT
  batching and threading chunking), and needs a rocFFT/cuFFT in-place story.
- It is, however, the largest-reach memory item on the table. If memory genuinely binds,
  un-archiving the OU consumer to make this concrete beats pursuing item 3.
- On the wider byte-level buffer-sharing framing: that is a scratch-arena design, and PF's
  stance is that the consumer owns buffers. An arena is solver-side.

## 5. Allocation-light radial diagnostics — SHIP

- Confirmed: 1.6 units, decomposing exactly into three materialized planes (magnitude², shell
  index, weighted product; 0.53 each).
- Fix: fuse all three into the shell-binning kernel (Cartesian ndrange, wavenumbers derived from
  the 1-D multipliers, fiber loop inside) → O(N) staging; the shell count computed analytically
  from the grid corner instead of a `maximum` over a materialized index field.
- `radial_correlation` gets the same treatment (its correlation field stays — it is the inverse
  transform's actual output). No new public surface.

## 6. Post-multiply kernel on `helmholtz_projection!` / `divergence!` — SHIP, α upgraded to the α/β pair

- The math clears PF's bar on its own terms: composing a per-mode operator with a scalar symbol
  is the product of Fourier symbols — the scalar ĝ passes through ℙ(k) (scalar·matrix) and ik·
  (scalar contraction) exactly. Composition, not convenience.
- Numbers reproduce: the standalone dealias is a read+write of the destination = 2 passes per
  evaluation, 6+6 per RK3 step under the mask strategies.
- Shape: **positional arities, not a `kernel = nothing` keyword** — PF operators don't carry
  keyword sentinels; the short form delegates per PF's α/β convention:
  `helmholtz_projection!(dest, f, multipliers, kernel[, α, β])`, same for `divergence!`.
- **The lone α becomes the full α/β pair, and that is load-bearing, not completeness.** The
  fused form *replaces* a `convolve!` that carries α/β — IT already rides the −∇· sign on
  `convolve!`'s α today (`Generator.jl:355`) — so shipping less would strand the chains it
  replaces. And β has a consumer the request didn't claim: **the entire phase-shift tail
  collapses into the two projection calls** —

  ```
  helmholtz_projection!(N̂, prod₁, mult, dealias,       ½, 0)   # primary
  helmholtz_projection!(N̂, prod₂, mult, dealias∘back,  ½, 1)   # displaced, accumulated
  ```

  with `dealias∘back` composed **once at setup** via the shipped kernel composition
  `convolve(dealias, back)` (both Hermitian, so the product is). The shift-back convolve, the
  ½/½ `combine!`, and the truncation convolve (`Generator.jl:253–255`) all vanish — ≈6 vector
  passes saved per evaluation, ×3 stages: three times the item's own claim for the masks. The
  scalar's displaced divergence fuses the same way through `divergence!`'s β.
- `curl!`'s deliberate absence is honored and recorded — consumer-driven absence is PF's rule.

## 7. Two-operand combine with a per-mode multiplier — SHIP the same-kernel form + the exponential twin

- The IF consumer is verified and is exactly the requested shape (`Propagator.jl:217+219`,
  `230+232`): `dest = ℰ ⊙ (α·a + β·b)` per stage per field; 6 vector + 6 scalar passes per RK3
  step. Coefficientwise ⇒ alias-safe; `b === dest` gives a kerneled accumulate for free — so
  there is **no** second trailing accumulate-α/β on top (two α/β roles in one signature is a
  known failure mode PF refuses).
- **Correction (a): the phase-shift consumer drops out — and was never an instance of this op.**
  As written, ½·primary + ½·kernel⊙displaced puts the kernel on *one* operand, which
  `ĝ⊙(α·a + β·b)` cannot express. It doesn't need to: item 6's α/β absorbs that chain
  entirely. Also, a **free 2-pass win available today with no new PF surface**:
  `Generator.jl:253–254` (shift-back convolve + ½/½ combine) is one existing call —
  `convolve!(nonlinear, shifted, back, ½, ½)` — the β path of the current `convolve!`.
- Correction (b): the exponential twin inherits the amended item-2 parameterization (no
  diffusivity, no substep, no "rate" crossing the boundary). One builder serves
  `exponential_convolve!` and the twin — "same kernel with an axpby prologue" is confirmed.
- Naming: `combine_convolve!` mashes two verbs; PF picks the final name at wiring (precedent:
  `symmetric_gradient`, a fused composition under one descriptive name; home `Convolution`,
  spectral-only). The proposed argument order (mirroring `combine!`, kernel last as in
  `convolve!`) is right.

---

## The general fusion API — DECLINED, as a recorded position

The natural follow-up to two rounds of fusion requests is "expose a general fusion mechanism and
stop shipping one-offs." PF considered it and declines. The reasons, for the record:

1. **It already exists, de facto, and that is the problem.** Julia's dot-broadcast fuses over PF
   fields today (a broadcast of fields returns a field, threaded, one pass) — and it is
   *unguarded*: `f̂ .* ĝ` on two fields in spectral representation compiles and runs, which is
   precisely the coefficientwise product PF's method set deliberately withholds as `*`. So the
   real question was never "build one" but "bless the one Julia gives us, or keep it internal."
   PF keeps it internal machinery, not a public contract (a documentation line will say so).
   Consumers should not reach for it — for IT that is also invariant 2 ("raise, don't
   reimplement") in disguise: a raw broadcast over field storage is an unverified kernel.
2. **A general fusion surface erases the spec.** PF's architecture is "the public method set is
   the spec — absences encode representation validity." A fusion API makes every combination
   expressible, including the invalid ones, and no type system can save it: a kernel *is* a
   `ScalarFieldSpectral`, so legitimate kernel application and the banned field×field product
   are indistinguishable at the type level. The one check types can express — physical never
   mixes with spectral in one broadcast — the broadcast styles already enforce.
3. **Verification doesn't fuse.** Each named operation carries what a client-composed kernel
   silently lacks: alias analysis, the α/β overwrite/accumulate branch, Nyquist handling (PF's
   translation kernel needed *both* wavenumber families to keep a displaced field real — a
   client-written symbol gets that wrong invisibly), the Hermitian-kernel reality condition,
   zero-allocation pins in the test suite, GPU parity, and bitwise threading identity. The
   triage protocol is where correctness actually happens — the phase-shift misfit in item 7 and
   the sign-α in item 6 were caught *because* a specific fusion was reviewed. A DSL compiles the
   wrong thing without comment.
4. **Demand is measurably exhausted.** Everything that survived triage instantiates one
   mathematical structure: sections in spectral representation form a **module over the ring of
   Fourier symbols**. The named operations now cover that structure — ring multiplication is
   kernel composition (`convolve(g₁, g₂)`), the ring-weighted combination is item 7, operator ∘
   symbol application is item 6. Once items 1/2/5/6/7 land, IT's own frozen ledger sits *at* its
   fused ideal. A general mechanism built now would be speculative structure with zero
   consumers.
5. **Two bounded escalation paths are recorded instead** — the validity-closed fragments of a
   general API, triggered by demand, not built now:
   - *Spectral: radial real symbols.* If a third functional form arrives (a Gaussian filter;
     hyperviscosity `exp(−ν(|k|²)^p τ)` is the plausible one), the exponential family
     generalizes to a closure `σ(|k|²)` — functions of the true `|k|²` are real and even, hence
     Hermitian-safe and Nyquist-unambiguous *by construction*.
   - *Physical: a stdlib-shaped `map!(φ, dest, sections...)`* — the section-valued sibling of
     PF's mapped reductions. In physical representation every pointwise fiber map is valid, so
     this fragment is validity-closed too. Waits for a consumer needing a fiber map outside the
     shipped algebra.

Operationally for IT: **the request protocol is the fusion API.** Keep raising named,
consumer-backed fusions; PF keeps triaging adversarially. Two rounds in, the protocol has caught
one wrong signature, one missing β, one boundary violation, and produced two fusions bigger than
requested — a compiler would have delivered none of that.

---

## Also relevant, already shipped on PF's side

- **Mapped reductions** (PF decision 30): every measure reduction now takes a leading fiber map —
  `mean(det, A)`, `maximum(norm, u)`, `integral(det, A)` — one fused pass, no intermediate
  section, faster than the materializing spelling on **both** backends (128³ F64: CPU 5.1 vs
  13.0 ms, GPU 0.55 vs 0.69 ms) at zero allocation. This is the lean route to derivative-invariant
  criteria (the skewness discussion that started round 1).
- **Compat floor 1.12** (PF decision 31) — and noted with approval that IT already matched
  (`75e1791`). The basis was measured, not assumed: 1.11 *runs* faster but *compiles* several
  times slower (PF's `Pkg.test()`: 31 min vs 5.4), a pure compile tax with nothing to fix on the
  package side.

---

# Postscript (2026-07-20): all five ships are built, verified, and pushed

The pin bump is ready. PF decisions 32–35; three commits on `master`.

- **Items 1+6** (`1a36689`, decision 32): the one-pass Helmholtz kernel — aliased in-place call
  guard-free and bitwise-identical, 2.7–6.5× the old three-broadcast form on CPU — and the
  kernel-composed arities `helmholtz_projection!`/`divergence!``(dest, f, mult, kernel[, α, β])`
  (positional arities, not a keyword; the α/β pair inherited from the `convolve!` they replace).
  The composed form costs +6–16% over the plain projection against ~+50% for the separate dealias
  pass. Reminder from your own note: the phase-shift wiring increment to check the re-frozen cells
  against is **4** passes/evaluation, your free win having banked 2.
- **Items 2+7** (`a072bc8`, decision 33): `exponential_convolve!`/`exponential_convolve` —
  `exp(c·|k|² + s·ŵ)` lazily from the wavenumber arrays, single-operand α/β + two-operand
  combination forms — and the kernel-composed `combine!(dest, α, a, β, b, kernel)` (a `combine!`
  method, the decision-32 trailing-kernel idiom; your argument order). One honest measurement you
  should see before wiring: the *fusion* forms win on both backends (kerneled `combine!` 1.5–1.7×,
  exp two-operand 1.4–1.5× GPU over the sequential pair), but single-operand lazy-vs-stored is a
  **reuse question** — with a varying exponent (your IF stages) lazy wins 1.4× once the stored
  route's rebuild pass is counted; with one fixed kernel applied many times, stored keeps 1.1×
  (GPU) to 2× (CPU, where `exp` is expensive). Full table: PF `PERFORMANCE.md` finding (k). For
  your per-stage-varying ℰ the lazy form is the right call and also retires `velocity_factor!`'s
  per-stage build.
- **Item 5** (in the closing commit, decision 34): the radial staging is gone — shell index, fiber
  contraction, and Parseval weight now derive per element inside the binning kernels, shell count
  analytic from the corner. `radial_spectrum` fell from three staged planes to its ~1.4 KB
  accumulator (now allocation-pinned tight); `radial_correlation` keeps only its substance (the
  power field + the inverse transform). Shell assignment is bitwise-unchanged.
- **The declines are recorded** (decision 35): the fusion-API position with your round-3
  reservation quoted verbatim-in-substance (the two-output stage update would pass PF's math bar;
  its open questions are the two-destination surface shape and the measured share), the item-3/4
  defers with reasons, and the broadcast-layer-is-internal statement now in `ARCHITECTURE.md` §8.

Every item: CPU t1+t4 suites green, GPU parity green on the RX 7900 XTX, allocation pins in place,
docs built with lints. Regenerate your compute cells against one pin at the closing commit.
