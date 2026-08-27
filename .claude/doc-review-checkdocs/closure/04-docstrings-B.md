# Closure grading — 04-docstrings-B (hat: docstrings-B)

Diff inspected: `git diff d03a2e9c..HEAD` (single commit `325851c0`).

## Finding 1

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `SeparableKernel` docstring. Before:
> "...kilobytes rather than the 129 MiB a `256^3` kernel would take, roughly the megabytes a `256^3`
> kernel would take — and applying it reads no FIELD-SIZED kernel stream..."

After:
> "...kilobytes rather than the 129 MiB a `256^3` kernel would take — and applying it reads no
> field-sized kernel stream: the three `O(N)` factors are read per mode, which is the saving, not zero
> kernel traffic."

The duplicated/contradictory "roughly the megabytes" clause is gone and the stray all-caps
"FIELD-SIZED" is normalized to lowercase backticked prose. Read the surrounding paragraph in full
(lines ~440–450 of the current file) — no residual contradiction remains.

**class_surfaces:** The finding is self-contained to one docstring (`SeparableKernel`'s magnitude
claim); its own text names no sibling surface (no other docstring is said to carry the same
stapled-together claim or an all-caps artifact). A targeted grep for other all-caps tokens embedded in
rendered docstrings (as opposed to `#` code comments, which are exempt from the rendering rule) found
none of this contradictory-magnitude class elsewhere in `src/`. Nothing further to sweep for this
specific finding.

## Finding 2

**Verdict:** HONORED

**Evidence:** `src/DifferentialOperators.jl` module docstring. Before, the opening flatly asserted
"the even-axis Nyquist term being zeroed" and the closing paragraph (elsewhere in the same docstring)
said squared wavenumbers keep the true value there — a direct self-contradiction. After:
> "...realized as a coefficientwise multiply by a wavenumber symbol with no finite-difference
> truncation. The two symbol families treat that Nyquist term differently and deliberately so (see the
> Nyquist split below), so it is not simply zeroed everywhere."

This explicitly retracts the blanket "zeroed" claim and points to the (already-correct) Nyquist-split
paragraph below it, resolving the contradiction within the same docstring.

**class_surfaces:** The finding's own text names only "opening claims" vs. "closing paragraph" within
this one module docstring — no sibling docstring is implied. Checked whether the same
over-general "Nyquist is zeroed" phrasing recurs unqualified elsewhere in `src/` (grep for
"Nyquist" + "zero" across `src/*.jl`): every other occurrence (`src/Fields.jl`, `src/Reductions.jl`,
`src/Convolution.jl`, `src/Interpolation.jl`) already correctly scopes the zeroing to the
*derivative*-wavenumber family specifically, not to "each operator" or "every symbol" in general, so
none of them carries this finding's specific defect (a blanket claim contradicted elsewhere in the
same text). The named site is the only instance of the class.

## Finding 3

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `radial_kernel` docstring — the bulleted `The arguments are:` list
for `sigma`/`multipliers` (2 positional args, no keyword) is replaced with running prose: "Here `sigma`
is a function of one real argument — the squared wavenumber `|k|^2` — returning a real value, and it
must be pure and GPU-safe... The `multipliers` are the `FieldSpectralMultipliers` supplying `|k|^2`...".
Matches rubric shape rule 1 (fewer than three arguments and no keyword ⇒ prose, no bullets).

**class_surfaces:** Findings 3, 4, 5 are explicitly the same class, self-named by the panel
("Same class as radial_kernel") at three sites in the same file: `radial_kernel`,
`spectral_cutoff`, `translation_kernel` (all `src/Convolution.jl`). All three were converted to prose
in this diff (see findings 4 and 5 below), so the class as the panel itself scoped it (these three
sites) is fully swept. A broader check of every other `The arguments are:` bulleted docstring in the
package (grepped all 40 occurrences across `src/*.jl`) found no further 2-positional-arg/no-keyword
docstring still wrongly using the bulleted form — every remaining bulleted docstring either documents
≥3 positional arguments (e.g. `spectral_band(multipliers, wavenumber_low, wavenumber_high)`,
`translation_kernel!(kernel, multipliers, offset)`, all three-arg persistence writers) or carries a
keyword argument (`with_threading(f; enabled=true)`).

## Finding 4

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `spectral_cutoff` docstring — bulleted list for `multipliers`/
`wavenumber_cutoff` (2 args, no keyword) replaced with: "Here `multipliers` is the
`FieldSpectralMultipliers` whose grid, Fourier layout, element type and array backend the kernel takes
as its own, and `wavenumber_cutoff` is the cutoff wavenumber `k_c` — a mode is kept when `|k| ≤ k_c`."

**class_surfaces:** Same class as finding 3, see that entry — `radial_kernel` (src/Convolution.jl) and
`translation_kernel` (src/Convolution.jl) are the sibling sites named by the panel's own "same class"
language; both were also fixed in this diff. Fully swept.

## Finding 5

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `translation_kernel` docstring — bulleted list for `multipliers`/
`offset` (2 args, no keyword) replaced with running prose: "Here `multipliers` is the
`FieldSpectralMultipliers` whose grid, Fourier layout, element type and array backend the kernel takes
as its own, and `offset` is the displacement `h = (h_1, h_2, h_3)`...".

**class_surfaces:** Same class as findings 3/4 — `radial_kernel` and `spectral_cutoff`
(both src/Convolution.jl), both fixed in this diff. Fully swept.

## Finding 6

**Verdict:** HONORED

**Evidence:** `src/Reductions.jl` `inner` docstring admonition. Before: `!!! note "The mixed spectral
pair allocates two correction planes"` unconditionally claiming two planes. After: `!!! note "The
mixed spectral pair allocates one or two correction planes"` with body: "materializes `O(N^2)`
correction planes — the folded axis's zero plane always, and its Nyquist plane as well when that axis
has even length, so an odd folded axis pays for one plane and an even one for two." This correctly
states the even_fold-gated behaviour the finding pointed at, both in the title and the body.

**class_surfaces:** The finding is specific to `inner`'s own note about its mixed-pair allocation
count; its text does not name a sibling docstring repeating the same "two correction planes" claim.
Checked: `l2norm`/`weighted_inner`/other Reductions docstrings do not repeat this specific
plane-count claim. No further surface implied or found.

## Finding 7

**Verdict:** HONORED

**Evidence:** `src/Reductions.jl` `weighted_inner` docstring — the `weights` bullet is added to the
signature-driven argument list: "`weights` — in the tuple form, a tuple of such kernels: every one is
answered in a single traversal and one device readback, bitwise-equal to calling the operation once
per weight, and the results are returned in the order given." Verified against the actual method
`weighted_inner(f::AbstractFieldSpectral{T}, weights::Tuple{Vararg{SpectralKernel{T}}})` — the
parameter name and behaviour described (tuple-of-kernels, one traversal) match the code.

**class_surfaces:** The finding's own text ("absent from the signature-driven bullets") names only
this one parameter on this one docstring — no sibling function or convention is implied. The general
argument-coverage rubric this instantiates is a project-wide rule, but the finding itself does not cite
other violations of it, so nothing further is in scope for this specific finding.
