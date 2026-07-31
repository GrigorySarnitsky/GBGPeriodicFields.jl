# Review — GPU-kernel / performance practitioner hat

Scope: allocation-free `!`-contract, backend parity (CUDA/ROCm/FFTW), scalar-indexing/`similar` GPU
portability, kernel fusion (lazy `|k|²`, fused spectral kernels), transform-plan reuse, the
memory-bound performance model and its per-platform numbers, Float32/Float64 as a studied axis.

Overall the performance/GPU story is unusually coherent across pages — the HIST step-times (192³→34 ms,
256³→87 ms on the 6700 XT; 320³→96 ms on the 7900 XTX), the ~384 GB/s / 96 MB-cache figures, the
~12 %-of-peak interpolation bandwidth, the loop-order (1.6×/3.9×) and sorting (0.5–1.0×) results, the
lazy `_squared_wavenumber_broadcast`, the SMatrix-by-value spline coefficients, the host-built
wavenumbers copied via `similar`+`copyto!`, and the CPU-based `@allocated` audit rationale all
reconcile. The findings below are the exceptions.

---

## Finding 1 — `symmetric_gradient!` is called allocation-free everywhere except the Performance coverage table, where it is grouped with the allocating wrappers

- type: contradiction
- severity: major
- confidence: high

**Locations / quotes**

- PAGE performance, §7 "Current coverage and known gaps" (line 769): *"The decision-27 additions
  (`combine!`, `det!`, `symmetricgradient!`,`weightedinner`) are wired into their classes and
  CPU-verified (0 allocations for `combine!`/`det!`; **the small bounded wrappers for
  `symmetricgradient!`/`weighted_inner`**); they enter the committed `RESULTS.md` table on its next
  GPU-host refresh."*  → puts `symmetric_gradient!` in the *bounded-allocating* bucket, next to
  `weighted_inner`, and pointedly NOT in the "0 allocations" bucket with `combine!`/`det!`.
- PAGE architecture, §13 decision 27 (line 470): *"the `test/allocations.jl` guard
  (`combine!`/`det!`/`symmetric_gradient!` **allocation-free**; `weighted_inner` allocation-light —
  only a small per-axis weight vector …)"*  → `symmetric_gradient!` is allocation-free.
- PAGE testing, §2 layout (line 808): the comprehensive `@allocated` audit that *"allocates ∼0 bytes"*
  covers *"the entire in-place `!` surface — spectral operators (**incl. `symmetric_gradient!`**),
  transforms, `convolve!`, …"*  → allocation-free (∼0 bytes).
- PAGE performance, §4(f) (line 725): *"The fix made the in-place spectral operators allocate nothing"*
  and §5 (line 737) lists *"spectral operators (including the fused `symmetric_gradient!`)"* — so the
  Performance page's own §4/§5 place `symmetric_gradient!` among the allocation-free spectral
  operators, which §7 then contradicts.

**Contradicts:** performance §7 (line 769, "small bounded wrappers for symmetricgradient!") vs
architecture decision 27 (line 470, "symmetric_gradient! allocation-free") + testing §2 (line 808,
symmetric_gradient! in the ∼0-byte audit) + performance §4(f)/§5. Axis: allocation status
(allocation-free / ∼0 bytes vs bounded-but-nonzero per-call allocation).

**Description.** `symmetric_gradient!` computes `Ŝ_ij = (i/2)(k_j û_i + k_i û_j)` as a fused
per-component broadcast over the derivative-wavenumber views straight into a preallocated tensor
destination (exactly the `curl!`/`gradient!` pattern, no `|k|²`, no longitudinal solve). It is
genuinely allocation-free, and three of the four surfaces say so. Only the Performance coverage
sentence (§7) misfiles it as a "small bounded wrapper" alongside `weighted_inner` (which legitimately
allocates a per-axis weight vector). For a GPU practitioner reading the coverage table to decide what
is safe to call thousands of times in a preallocated device hot loop, "bounded wrapper" reads as "this
one allocates each call" — the opposite of the truth, and precisely the property the whole
allocation-free contract exists to guarantee. Fix: move `symmetric_gradient!` into the "0 allocations"
group with `combine!`/`det!`; leave only `weighted_inner` as the allocation-light one.

---

## Finding 2 — Decision 18 states the *mixed* spectral `inner(f̂, ĝ)` is "computed allocation-free"; decision 26 states the same mixed `inner(f, g)` allocates an O(N²) plane correction on the GPU

- type: contradiction
- severity: minor
- confidence: medium

**Locations / quotes**

- PAGE architecture, §13 decision 18 (line 406): *"for two fields in spectral representation
  `inner(f̂, ĝ)` equals the physical inner via the rfft half-spectrum Parseval weighting …, **computed
  allocation-free as a `dot` over the array plus two plane corrections**."*  (explicitly the two-field
  `f̂`/`ĝ` case.)
- PAGE architecture, §13 decision 26 (line 461): *"`inner(f, f)` … is allocation-free … **but the
  mixed `inner(f, g)` of two distinct fields allocates an O(N²) kₓ-plane correction**, because a `dot`
  over the strided plane view (which would fuse, no temporary) is unsupported on the GPU (rocBLAS
  `dotc` has no strided method — verified on the device)."*
- PAGE architecture, header of §13 (line 358): *"later entries supersede earlier "remaining"/"deferred"
  notes … **rather than contradicting them**"*, and §Documentation-policy (line 182) requires *"each §13
  decision-log entry reads on its own, without opening the source or another document."*

**Contradicts:** decision 18 (line 406, mixed spectral `inner` "computed allocation-free … plus two
plane corrections") vs decision 26 (line 461, mixed `inner(f, g)` "allocates an O(N²) kₓ-plane
correction … unsupported on the GPU"). Axis: whether the mixed spectral inner's plane corrections are
allocation-free (they fuse on CPU, but must be materialized on the GPU).

**Description.** The "two plane corrections" of decision 18 are exactly the strided-view `dot`s that
decision 26 says fuse on the CPU but cannot fuse on the GPU (no rocBLAS strided `dotc`), forcing an
O(N²) plane materialization. So decision 18's unqualified "computed allocation-free" is true only on
the CPU (where the audit runs); read on its own — as the decision-log mandate requires — it overclaims
for the GPU backend, which is the platform the package is optimized for. Decision 26 is the correct,
refined statement. Softening factor: the audit is CPU-by-design and this is the one documented
device-specific exception, so a reader who reaches decision 26 gets the full picture; hence minor /
medium. Suggest qualifying decision 18 ("allocation-free on the CPU; see decision 26 for the GPU plane
correction") or dropping the "allocation-free" clause there.

---

## Finding 3 — Backend-parity mismatch: the architecture says rocFFT preserves *both* transform directions, but the `to_spectral!` docstring names rocFFT as the example of a backend that scratches the forward (r2c) input

- type: contradiction
- severity: minor
- confidence: low

**Locations / quotes**

- PAGE architecture, §4 "Spectral machinery" (line 250): *"It is also backend-divergent — verified
  that AMD/rocFFT (via AMDGPU.jl) **preserves both directions on tested sizes**, while FFTW does not."*
- PAGE api / Fields, `to_spectral!` (line 2390): *"The forward transform may overwrite `physical` on
  some backends (**for example rocFFT reserves the right to use real-to-complex inputs as scratch**);
  the FFTW CPU backend preserves it, but do not rely on the source surviving."*
- (Consistent counterpart: `to_physical!`, line 2364, hedges the inverse direction as *"some GPU
  backends happen to preserve them"* — so the inverse direction is stated compatibly; the conflict is
  only on the forward/r2c direction.)

**Contradicts:** architecture §4 (line 250, "rocFFT … preserves both directions") vs Fields
`to_spectral!` docstring (line 2390, "rocFFT reserves the right to use real-to-complex inputs as
scratch"). Axis: whether rocFFT preserves the forward (r2c) transform input.

**Description.** The architecture holds rocFFT up as the backend that preserves *both* directions (in
contrast to FFTW); the `to_spectral!` docstring picks rocFFT as the concrete example of a backend that
*may scratch* the forward r2c input. These can be reconciled ("empirically preserves on tested sizes"
vs "the contract reserves the right"), but the surface reading is contradictory, and choosing rocFFT
specifically as the r2c-scratcher example directly undercuts the architecture's rocFFT claim. Because
the safe contract ("do not rely on a `!`-transform's source surviving") holds either way and this is a
narrow backend-attribution nuance, I mark it low confidence. Reconcile the two: either soften §4
("rocFFT preserved both on tested sizes but reserves the right to scratch") or use a neutral example in
`to_spectral!` instead of naming rocFFT.

---

## Finding 4 — CUDA compute-capability label written inconsistently as `sm120` and `sm_120`

- type: format
- severity: nit
- confidence: high

**Locations / quotes**

- PAGE performance, §6 (line 757): *"the RTX 5070 Ti (Blackwell **sm120**, CUDA, 16 GB)"*.
- PAGE performance, §7 (line 769): *"RTX 5070 Ti (Blackwell **sm120**, CUDA)"*.
- PAGE performance, §7 (line 774): *"the RTX 5070 Ti (Blackwell **sm_120**, 16 GB)"*.

**Contradicts:** performance §6/§7 "sm120" (lines 757, 769) vs performance §7 "sm_120" (line 774).
Axis: spelling of the CUDA architecture tag for the same card.

**Description.** The same Blackwell architecture is written `sm120` twice and `sm_120` once, all on the
Performance page. The CUDA-toolchain canonical form is `sm_120`. Pick one spelling and use it
throughout.
