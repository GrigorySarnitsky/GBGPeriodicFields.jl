# Consistency-matrix audit — hat: consistency-matrix

Reviewer note: this document is unusually self-consistent — nearly every recurring
formula, method count (206/122), citation, and notation convention I cross-checked
(det formula, Nyquist split, N/M interpolation adjoint, method-count progression
198→202→206 and 118→120→122, K41 dimensional form, `\partial_{x_i}` notation, kernel
storage-class sizes) agreed verbatim or exactly-as-expected across every page that
restated it. The findings below are the genuine divergences that survived that
cross-referencing pass.

---

## Finding 1 — "every/each reduction" gets a mapped form, contradicted by "five reductions only" stated three other places

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high

**Locations (the overclaim, 3 sites):**
- PAGE: architecture, §12 Reductions: *"`mean`/`std`/`var`/`cov` (extending `Statistics`) and `maximum`/`minimum`/`extrema` (extending `Base`) are the moments... **Each reduction additionally has a mapped form** taking a leading function... (decision 30)."*
- PAGE: architecture, decision log (decision 30's own title/opening sentence): *"Mapped reductions — a leading function on **every measure reduction**... **So each reduction gained a form** taking a leading function..."*
- PAGE: api / Reductions, module docstring bullet list (directly under the `std`/`var`/`cov` and `inner` bullets): *"The mapped forms — **each reduction above** also accepts a leading function..."*

**Locations (the correct, narrower claim, contradicting the above, 3 sites):**
- PAGE: architecture, same decision-30 entry, two sentences later: *"`Statistics` gives `var` and `std` no such method, so **neither does this package**... so `mean`, `maximum`, `minimum`, `extrema`, and the package's own `integral`... take one."*
- PAGE: api / GBGPeriodicFields (umbrella): *"**Five of them** — `integral`, `mean`, `maximum`, `minimum` and `extrema` — also take a leading fiber map... **the others have no mapped form**."*
- PAGE: api / Reductions, page footer (just before "Internal API"): *"**Five of the reductions** — `integral`, `mean`, `maximum`, `minimum` and `extrema` — also have a mapped form... `Statistics` gives `var` and `std` **no such spelling**, so neither does this package."*

**Description:** Read literally, "each reduction above" (Reductions page) sits directly
below bullets for `std`/`var`/`cov` and `inner`, and "every measure reduction" /
"each reduction" (Architecture §12 and the decision-30 title) sit in paragraphs that
just enumerated `inner`, `mean`/`std`/`var`/`cov`, and the radial pair — so a reader
would conclude `var(det, A)`, `cov(det, A)`, `inner(norm, u, v)`, `weighted_inner`,
`l2norm`, `radial_spectrum`, and `radial_correlation` all accept a leading function.
Three other passages (two on the very same pages) state explicitly that only five
reductions (`integral`, `mean`, `maximum`, `minimum`, `extrema`) have this form and
that `Statistics` giving `var`/`std` no such spelling is the reason this package
gives them none either. A user following the "each reduction above" sentence would
write code that throws a `MethodError`.

**resolution_hint:** Reword the two overgeneral sentences (Architecture §12's "Each
reduction additionally has..." and the Reductions page's "each reduction above") to
name the five explicitly or say "five of the reductions above", matching the correct
wording already used at the decision-30 entry's own follow-on sentence, the umbrella
page, and the Reductions page's own footer.

---

## Finding 2 — `SeparableKernel`/`materialize_kernel` crossover point stated as "past 128³", but the cited benchmark table shows the CPU-threaded `Float64` crossover already past by 128³

- **Type:** performance
- **Severity:** minor
- **Confidence:** medium

**Locations:**
- PAGE: api / Convolution, `SeparableKernel` docstring: *"threaded on a CPU it runs at roughly $0.5$–$0.6$ of its speed at $64^3$, **crosses one somewhere past $128^3$**, and is $1.1$–$1.2$ times faster at $256^3$–$512^3$."* (repeated near-verbatim in `materialize_kernel(::SeparableKernel)`'s docstring: *"crosses one somewhere past $128^3$... 1.1–1.2 times faster at 256³–512³"*)
- PAGE: performance, finding (o) table: CPU t8 F64 column reads `0.62` (64³), **`1.44` (128³)**, `1.15` (256³), `1.12` (512³) — i.e. for `Float64` at 8 threads the ratio is already `>1` (axis-factored faster) **at** 128³, not "past" it, and in fact dips back down at 256³–512³ rather than climbing to the quoted "1.1–1.2×".

**Description:** The docstring's single "crosses somewhere past 128³... 1.1–1.2× at 256–512³" narrative is a summary that does not fit the `Float64`/`t8` column of the table it is built from (crossing at/before 128³, then receding toward 1.15–1.12×, not climbing from a sub-128³ crossing to 1.1–1.2×). It fits the `Float32` columns better (0.50 at 128³, 1.18/1.12 at 256–512³). The docstring does not specify which type/thread combination its summary describes, so as written it reads as a universal claim that one concrete column contradicts.

**resolution_hint:** Either qualify the docstring's crossover claim by element type ("for Float32; Float64 threaded crosses earlier"), or soften "past 128³" to "around 128³".

---

## Observations that did *not* rise to reportable findings (recorded for completeness of the matrix)

- Method-count progression (198→202→206 field methods; 118→120→122 point-value
  methods) is internally consistent everywhere it is cited, including the
  decision-log's historical snapshots at each stage — no drift found.
- The determinant formula $\det A = \varepsilon_{ijk}A_{1i}A_{2j}A_{3k}$ is restated
  identically in Architecture, `FiberSections._det_tensor_rhs`, and
  `FieldAlgebra.det!` — no drift.
- The Nyquist-split rule (derivative wavenumber zeroed, squared wavenumber kept true)
  is restated identically across Architecture §4, Formalization, the
  `DifferentialOperators` module page, and `Convolution`'s `translation_kernel` — no
  drift.
- The interpolation/anterpolation measure-adjoint identity
  $M\langle Wf,q\rangle_{\mathrm{pts}} = N\langle f, W^\top q\rangle_{\mathrm{grid}}$
  is derived once in Formalization and restated verbatim (same symbols, same
  ordering) in the `Interpolation` module page and Architecture §10 — no drift. (The
  Formalization page explicitly flags the *unweighted* form as the false "slip" this
  same identity guards against, and no page anywhere asserts the false form as true.)
- Kernel-size figures (129 MiB / 10 KiB at 256³, 16.2 MiB / 5 KiB at 128³, 144-byte
  wrapper cost) recur identically across the decision log and three `Convolution`
  docstrings (`SeparableKernel`, `RadialKernel`, `materialize_kernel`, `StoredKernel`)
  — no drift.
- The CUDA-vs-ROCm `radial_spectrum` Float64 figure (65.95 ms → 1.371 ms, ~48×)
  recurs identically in two Performance-page locations — no drift.
- K41 spectrum guide $C_K\varepsilon^{2/3}\kappa^{-5/3}$ is dimensionally complete and
  carries its constant everywhere it appears (notation page and the HIST example) —
  no drift, consistent with the project's own standing style rule.
- `\partial_{x_i}` (never bare `\partial_i`) is used consistently in every
  differential-operator formula I found (gradient, divergence, symmetric_gradient,
  Laplacian) — no drift from the banned-variant rule.
