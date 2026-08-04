# Consistency-matrix hat — findings

Reviewer role: systematic consistency auditor. Method: built an entity matrix (symbols,
formulas, normalizations, method-count baselines, kernel-class taxonomy, benchmark figures)
and diffed each entity's every occurrence across all pages of the rendered site
(`Home`, `api overview`, `architecture`, `formalization`, `notation`, `performance`, `testing`,
`tutorial`, all `api/*` module pages, `examples/hist_cpu`).

Overall note: this codebase's docs carry an unusually dense, self-auditing decision log (dozens
of internal correctness sweeps already recorded), so most candidate "contradictions" turned out,
on expansion, to be chronological narration (a count stated at time T, superseded and correctly
re-stated at time T+1) rather than live inconsistencies. The findings below survived that
expansion.

---

## Finding 1 — the CUDA-over-ROCm `Float64` radial-spectrum speedup is given as two different numbers for the same measurement

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: performance, §4 finding (n): *"the ~80× CUDA-over-ROCm `Float64` radial gap, which is this kernel under RDNA3's CAS-loop `Float64` atomics"*
  - PAGE: performance, §6 (representative-slice discussion): *"widening to ≈49× in `Float64` (67.1 → 1.38 ms)"* — for *"`radial_spectrum` on a vector field at 256³"*, RTX 5070 Ti vs RX 7900 XTX.
  - PAGE: performance, §7 (gaps): *"`radial_spectrum` vector `Float64` 256³ is 65.95 ms on the 7900 XTX against 1.371 ms on the 5070 Ti — a ~48× CUDA lead"*
- **Contradicts:** all three passages describe the identical benchmark cell (`radial_spectrum`, vector field, `Float64`, 256³, RTX 5070 Ti vs RX 7900 XTX) — §6 and §7 (independently, ~2% apart, consistent with the doc's own documented ~10% run-to-run jitter) both land at **~48–49×**, while §4 finding (n), in the same page, cites **~80×** for what its own wording ("this kernel", "`Float64` radial gap") identifies as the same comparison.
- **Description:** A reader citing "the CUDA/ROCm radial gap" from this page gets two different numbers depending which paragraph they read, and neither passage flags the other as measuring something different (a different grid size, kernel, or metric). If finding (n)'s 80× is a genuinely different quantity (e.g. a different metric than wall-clock ms, or drawn from an older archive), the text should say so explicitly; as written it reads as the same fact stated two ways.

---

## Finding 2 — `ProductKernel`'s stated general rule contradicts the specific composition rule given for two `StoredKernel`s

- **Type:** contradiction
- **Severity:** major
- **Confidence:** medium-high
- **Locations:**
  - PAGE: api / Convolution, `ProductKernel` type doc: *"what `convolve` returns when it composes kernels that are not both of one family"*
  - PAGE: api / Convolution, `convolve!` docstring (the "Two kernels compose…" admonition): *"every other pair — two stored kernels, a cross-family pair, or radial operands failing that test — becomes a `ProductKernel`"*
- **Contradicts:** `ProductKernel`'s own definition says it is what results when the two operands are **not both of the same family**; but `convolve!`'s docstring explicitly lists **two `StoredKernel`s** (both of the same family, `StoredKernel`) as one of the cases that "becomes a `ProductKernel`". The two same-family compositions the `ProductKernel` doc does bother to enumerate (two `SeparableKernel`s, two same-coordinate `RadialKernel`s) both collapse into a single kernel of that family — so its lead sentence reads as a complete rule that the stored+stored case falsifies.
- **Description:** This is a genuine definitional gap, not just missing detail: a user reading `ProductKernel`'s docstring alone would conclude `convolve(stored1, stored2)` returns a `StoredKernel` (same family ⇒ stays in family), while `convolve!`'s own docstring says the opposite. The design rationale (avoid eagerly materializing a second `O(N^3)` array) makes the `convolve!` version plausible/likely correct — which makes `ProductKernel`'s summary sentence the one that needs fixing (either to state the exception, or to be reworded so it does not imply same-family always collapses).

---

## Finding 3 — the `SeparableKernel`/`materialize_kernel` crossover summary does not match its own cited benchmark table

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Convolution, `materialize_kernel(kernel::SeparableKernel)`: *"runs at roughly $0.5$–$0.9$ of its speed at $64^3$–$128^3$, reaches parity near $256^3$, and is $1.1$–$1.2$ times faster at $256^3$–$512^3$"*
  - PAGE: performance, §4 finding (o) table: at $64^3$, `GPU F64 = 0.98`, `CPU t1 F64 = 0.44`; at $128^3$, `GPU F64 = 0.79`; at $256^3$, `GPU F32 = 1.01`.
- **Contradicts:** the docstring's summary range (0.5–0.9 at 64³–128³, "parity" at 256³, 1.1–1.2× beyond) is contradicted by several cells of the very table it is presumably summarizing: `CPU t1 F64` at 64³ is **0.44** (below the stated 0.5 floor), `GPU F64` at 64³ is **0.98** and at 128³ is **0.79** (both well above the stated 0.9 ceiling, and neither near the docstring's implied crossover), and `GPU F32` reaches only **1.01** at 256³ (not the "1.1–1.2×" the docstring claims for that size class).
- **Description:** The docstring appears to summarize only the CPU-threaded / production-relevant rows and silently drop the GPU-`Float64` and CPU-single-thread rows, which sit outside the quoted range. As a standalone summary this is misleading about which regime it covers; the same table is directly one page away.

---

## Notes on candidates investigated and NOT flagged (for the record)

- The **206/122-method public-surface counts**, and their historical predecessors (98, 198, 202,
  118, 120), are internally consistent once read as a chronological decision log — each is
  explicitly qualified with "from N" or a decision number, and the final, current numbers (206
  field / 122 point-value) are used consistently everywhere the *current* state is asserted
  (Architecture, Testing, several module docstrings).
- The **Home page vs `api overview` page module-list bullets** differ substantially in verbosity
  but not in claimed content (Home is the discursive "map", the overview is the terse index) — not
  a contradiction under the docs' own stated two-tier policy.
- The **turbulent-kinetic-energy $k$ vs wavenumber $k$** notation collision in the `hist_cpu`
  example is explicitly declared as a local override on both the Notation page and the example
  itself — consistent, not a finding.
- The **`~80×`/`~220` vs `223`** shell-count and other "≈" figures elsewhere are explicitly
  hedged as approximations against an exactly-stated companion figure — not a contradiction.
