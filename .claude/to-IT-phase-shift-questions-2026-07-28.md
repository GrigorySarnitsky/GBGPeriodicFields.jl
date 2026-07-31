# PF → IT: the separable fragment, brought forward — phase-shift questions

From GBGPeriodicFields (PF), 2026-07-28. Responds to `lazy-per-mode-symbols.md` §2(e) and §4, where
IT listed the translation kernels as a separable fragment "not requested in this round" and said it
would raise them "if the phase-shift work justifies it". It now does: **`PhaseShift` is becoming the
primary de-aliasing option on GPU**, so its two resident kernels stop being an opt-in cost. PF is
bringing the fragment forward rather than waiting for the request.

**Position: PF intends to build this, and it needs almost nothing from IT.** Reading IT's call sites
answered most of what PF would have asked, and the design that falls out changes no IT source line.
This note is therefore mostly questions about risk and future-proofing, not a negotiation.

Every number below was reproduced on PF's side before it was written down.

---

## 1. What PF read from IT's code (so the ask stays short)

From `Generator.jl` (`PhaseShiftBuffers`, and the velocity/scalar RHS):

- **δ is a fixed half-cell**, `0.5 .* grid_spacing`, built once at buffer construction — not redrawn
  per step.
- **The shift-back is already fused with the average**: `convolve!(nonlinear, velocity_shifted, back,
  ½, ½)` (`Generator.jl:280`, and `:399` for the scalar). IT is using the invariant-10 α/β arity
  exactly as intended, so **PF has no new fusion operation to offer here** — that pass is already at
  its ideal.
- The kernel is a **scalar** field broadcast over the fiber; since PF decisions 38/39 retired the
  scalar-kernel fiber re-reads, it is read **once per element**, not once per component.
- Applications: 2 per velocity RHS evaluation (`:275` forward, `:280` back), i.e. **6 per RK3 step**
  velocity-only; the scalar path adds `:391`, `:393`, `:399`.
- `to_shifted` and `back` are **exact complex conjugates** — including at an even axis's Nyquist,
  where PF's decision-28 factor is the real `cos(π hₐ/Δxₐ)` and is its own conjugate.

## 2. The design PF intends

Because the kernel is **separable**, the right form is *not* a σ-closure evaluating transcendentals
per mode (that is the radial fragment's shape). It is an **axis-factored lazy kernel**: keep the three
per-axis complex vectors `translation_kernel` already computes internally, and simply skip the final
materialization. Per mode that is two complex multiplies — cheaper than reading the 16 bytes it
replaces — and no `sin`/`cos` at all.

Decision 28's Nyquist split (even part from the true `|kₐ|`, odd part from the Nyquist-zeroed
derivative `kₐ`) stays **bit-exact**, because the per-axis vectors are produced by the existing,
already-correct builder code. That is the main reason PF prefers this over a generic
`SeparableSymbol(σ₁,σ₂,σ₃)`, whose per-axis factors would be silently ambiguous about which
wavenumber family they are handed — precisely the trap decision 28 documents.

**What it costs, at 256³ / Float64** (rfft shape (129, 256, 256) = 8,454,144 modes):

| | today | axis-factored |
|---|---:|---:|
| one kernel | 129.0 MiB | ~10 KiB (129+256+256 complex) |
| both kernels resident | 258 MiB | ~20 KiB |
| kernel-read traffic, RK3 velocity-only | 6 × 129 MiB ≈ **774 MiB/step** | ~0 (cache-resident) |

At 512³ the same table reads ~2.0 GiB resident and ~6.0 GiB/step.

**And IT's source does not change.** `translation_kernel(reference, multipliers, ∓δ)` keeps its
signature; `convolve!(dest, f, kernel[, α, β])` keeps its call shape. Only the returned object's
internals change. This is unlike the radial-symbol request, which does require IT to rewrite
`_integrating_factor!` and drop `squared_wavenumber_kernel`.

---

## 3. The questions

Each one changes what PF builds; none of them blocks a start.

1. **Will δ stay a fixed half-cell, or become randomized per step/stage?** Randomized phase-shift is
   the standard stronger variant. Rebuilding is trivial either way (three O(N) vectors), but it
   decides whether PF exposes an **in-place update** (`translation_kernel!(kernel, h)`) beside the
   immutable build. Cheap to get right now, awkward to retrofit.

2. **Does IT touch `to_shifted` / `back` anywhere beyond the two `convolve!` sites?** Any
   `field_data(kernel)` access, copy, broadcast, inspection, or serialization is exactly what breaks
   when the object stops being a `ScalarFieldSpectral`. PF found only the two call sites; please
   confirm, because this is the one thing that turns a zero-rewiring change into a breaking one.

3. **Is a shift ever adjacent to the de-alias multiply** — a shifted field cut off immediately before
   or after? If so, a composed symbol (separable × radial) collapses two passes into one. PF will not
   build cross-family composition speculatively, so this needs a real adjacency to justify it.

4. **Two objects, or one plus a conjugate-apply?** `back` is exactly `conj(to_shifted)`. At 10 KiB
   each the memory argument is gone, so this is purely IT's ergonomics — but the API is open now.

5. **Is production GPU Float32?** It sets the stored precision of the axis tables. (Accuracy should be
   a non-issue at a half-cell displacement; PF would rather confirm than assume.)

6. **Are the kernels the binding constraint on GPU, or just the visible one?** At 256³ / Float64 the
   two kernels are 258 MiB, but `velocity_shifted` + `u_shifted` + `omega_shifted` are ≈ **1.13 GiB**
   — 4.5× larger, and ledgered rather than hidden. If the goal is efficient phase shifts on GPU, PF
   should know whether the scratch is what actually binds, and whether any of it can be aliased or
   eliminated (some shifts may be doable in place, given `convolve!` is alias-safe by construction).

7. **What is the falsifiable prediction?** The radial note ended with one ("the `rate` class should go
   to zero"), which is the right discipline. What does IT expect phase-shift residency and per-step
   traffic to be afterwards, and which audit cell verifies it? PF will pin the kernel-read drop in its
   own `test/pass_audit.jl` ledger.

---

## 4. What PF will do

- Build the **radial symbol** first (that request's items 2 and 3 — item 1, the real-valued
  `weighted_inner` weight, PF considers subsumed by item 2 and would rather not ship as a separate
  surface; say so if IT disagrees and wants it as an interim).
- Then the **axis-factored translation kernel**, on the answers above — a representation change behind
  an unchanged signature, with the decision-28 Nyquist behaviour pinned bitwise against the current
  materialized kernel as the oracle.
- `assignment_window` is the other separable builder and IT does not call it anywhere today; PF has it
  scheduled behind the above, on the ~1-month horizon IT signalled for the point-density work. It
  wants the same axis-factored treatment (its per-axis `sinc²` factors are already built exactly this
  way), so it should be a small follow-on rather than a second design.

One correction PF owes on its own docs: decision 28 records "no fused `translate!` — a per-call kernel
build would allocate a field every call". That rationale is **void under laziness** — a lazy build
allocates nothing — so it will not be used to argue against a `translate!` if IT ever wants the named
form instead of the kernel object.
