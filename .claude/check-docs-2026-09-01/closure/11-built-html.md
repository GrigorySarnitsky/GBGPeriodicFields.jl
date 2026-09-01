RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/api/FiberSections.md`:
  ```
  -These symbols are not part of the public interface; they are documented for contributors — the CPU-threading primitives and the fiberwise-algebra code generators, for anyone extending the package's algebra.
  +These symbols are not part of the public interface; they are documented for contributors — the
  +CPU-threading primitives, the fused fiberwise executor that every stamped operation runs through, the
  +fiberwise-algebra code generators, the section-introspection helpers, and the storage-ownership check
  +that keeps aliasing safe by construction, for anyone extending the package's algebra.
  ```
  The blurb now names all five families the finding's evidence enumerated: CPU-threading primitives,
  the fused fiberwise executor (decision 39's machinery), the code generators, the section-introspection
  helpers (`section_scalar_type`, `section_tensor_order`, `_fiber_type`, `_fiber_order`), and the
  storage-ownership check (`_check_owned_storage`, decision 59). Nothing from the evidence list is left
  unnamed.
- **class_surfaces:** The finding's own rule ("check 4 of surface 6 — an Internal API blurb is
  hand-written while its list is derived, so the two drift silently") is a package-wide pattern that in
  principle applies to every module page with an Internal API section: `docs/src/api/Fields.md`,
  `docs/src/api/Points.md`, `docs/src/api/FieldAlgebra.md`, `docs/src/api/Reductions.md`,
  `docs/src/api/DifferentialOperators.md` (each has its own blurb). The finding itself does not name
  these as defective — the same banked file's "Verified clean" section (lines 83-87) already audited
  all five and found each blurb complete, so no fix was owed there. Confirmed via
  `git diff ac1226e4..HEAD --stat -- docs/src/api/`: only `Convolution.md`, `FiberSections.md`,
  `Interpolation.md` changed — the five already-clean pages are untouched, which is the correct
  outcome given the pre-existing census, not a missed sweep.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/api/Interpolation.md`:
  ```
  -small linear solve), the periodic cell-finding, and the in-kernel helpers.
  +small linear solve), the periodic cell-finding, and the compatibility checks the transfer verbs route
  +through.
  ```
  The false "in-kernel helpers" clause (the block actually holds no in-kernel helpers) is replaced with
  a clause describing the two compatibility checks the block does hold
  (`_check_nufft_compatibility`, `_check_transfer_colocation`), matching the finding's fix instruction
  and evidence. The other three clauses (`AbstractSplineScheme`; the Fornberg/weight generators; the
  cell-finding) were already correct and are left untouched.
- **class_surfaces:** Same general rule as Finding 1 (drift between a hand-written blurb and its
  derived `@autodocs` content). The finding names no other surface than this one blurb; the banked
  file's own census (lines 83-87) already found the other module blurbs (`Fields`, `Points`,
  `FieldAlgebra`, `Reductions`, `DifferentialOperators`) clean, and the diff leaves them untouched
  (confirmed above), which is the expected, non-deficient outcome — no other site is implied by this
  finding's text as needing a matching edit.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/api/Convolution.md`:
  ```
  -coefficientwise convolution, combination and exponential-kernel bodies, and the axis-factored pair
  -that evaluates a separable kernel per mode.
  +coefficientwise convolution, combination and exponential-kernel bodies, the axis-factored pair that
  +evaluates a separable kernel per mode, and the exponential kernel pair — a device kernel and its
  +gated CPU twin — that evaluates the mode factor once per mode rather than once per component.
  ```
  The finding's evidence named the previously-unlisted decision-79 kernel pair
  (`_exponential_convolution_modes!` / `_exponential_combination_modes!`) as the two of eight entries
  missing from the blurb ("The blurb was written before that decision and describes six of the eight").
  The new clause names exactly that pair, characterized correctly as a device kernel with a gated CPU
  twin (matching decision 79's own description elsewhere in CLAUDE.md). All six pre-existing entries'
  clauses are preserved verbatim.
- **class_surfaces:** Same general rule as Findings 1-2. The finding names no sibling surface beyond
  this one blurb; nothing elsewhere in the finding's text implies a second Convolution.jl location or
  another page needing the same decision-79 naming. The other module blurbs were already verified
  clean by the census and remain untouched in the diff.
