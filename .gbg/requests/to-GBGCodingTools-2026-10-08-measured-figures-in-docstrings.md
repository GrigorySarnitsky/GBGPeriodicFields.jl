Status: open — approved by the owner on 2026-10-08; sent to the GBGCodingTools session the same day.

# To GBGCodingTools: measured performance figures do not belong in a docstring

No rule says where a measurement goes. `RULE.DOC.HOME_ORDER` excludes implementation internals and
design rationale from a function docstring, and wants the caveats a user needs as admonitions; it does
not name benchmark figures. PF's own cost rule asked docstrings to state cost "with a concrete
quantitative anchor", meaning complexity, passes and comparison to a named operation. It never said
that a measured ratio is not such an anchor. Measured figures entered three of PF's docstrings through
that gap, and the owner found them on 2026-10-08.

## PF's case

- **How they arrived.** A feature commit (2026-07-19) put that day's benchmark ratios into
  `exponential_convolve!`. Later sessions, asked whether a cost note still held, re-derived the figures
  and wrote more precise ones back instead of asking whether they belonged (2026-09-03). This happened
  in the `exponential_convolve!`, `RadialKernel` and `materialize_kernel` docstrings. A documentation
  review then polished their wording (2026-09-24). Each step corrected a stale or false number, so each
  looked right on its own.
- **What they looked like.** Paragraphs of ratios by grid size, thread count, element type and GPU
  model, for example "0.88–1.03 of a stored kernel's time at 256³–512³" and "1.20–2.53× at every size
  and element type measured", in the middle of the description a user reads first.
- **The worse half.** The re-derived figures existed only in the docstrings. `PERFORMANCE.md`, the
  package's home for measurements, still held the older table, so the docstrings had become the only
  record. They also go stale with every benchmark sweep, and nothing checks them against the archives.
- **What PF did.** Each docstring now gives the guidance the figures support, in words, where a user
  has a real choice (for one fixed kernel on a scalar field a stored kernel is usually faster; on a
  vector field the two are comparable). The figures moved, dated, to `PERFORMANCE.md` findings (k) and
  (o). One hardware gotcha, the `Float32` subnormal slowdown on a CPU, stays as a short warning.

## What is asked

A rule, fleet-wide, and a check if one fits its shape:

- A docstring states cost structurally: asymptotic complexity, the number of passes, memory, and
  comparison with a named operation ("one pass", "comparable to one `inner`", "O(N) rather than
  O(N³)").
- Where the faster choice depends on the case, the docstring says which way in words.
- Measured ratios, timings and throughputs, and the hardware they were measured on, go to the
  package's performance document. The docstring may link there.
- A possible check: numeric ratios (`1.2×`, `0.88–1.03`), times (`ms`, `µs`) and rates (`GB/s`) inside
  docstring prose. Asymptotic forms, memory sizes and tolerances must not trip it.

The design is the tool's.
