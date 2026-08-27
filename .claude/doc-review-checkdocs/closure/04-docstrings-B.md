RANGE: d03a2e9c..HEAD

## Finding 1

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl`, `SeparableKernel` struct docstring. Diff hunk:
```
 of ``O(N)`` entries in place of ``O(N^3)`` coefficients — kilobytes rather than the 129 MiB a ``256^3``
-kernel would take, roughly the
-megabytes a ``256^3`` kernel would take — and applying it reads no FIELD-SIZED kernel stream: the
+kernel would take — and applying it reads no field-sized kernel stream: the
 three ``O(N)`` factors are read per mode, which is the saving, not zero kernel traffic.
```
The duplicated/contradictory "kilobytes ... megabytes" staple is gone (single magnitude claim now:
kilobytes vs the 129 MiB a 256³ kernel would take), and the all-caps `FIELD-SIZED` artifact is now
lowercase `field-sized`. Read the current source at `src/Convolution.jl:441-448` — clean, single
coherent claim.

**class_surfaces:** The finding's own text names only the one docstring ("SeparableKernel docstring
has two contradictory magnitude claims stapled together... plus an all-caps FIELD-SIZED artifact") —
it does not name a sibling docstring, a family, or a repeated convention elsewhere. This reads as a
one-off editing/duplication artifact rather than a class with other instances, so there is no other
surface implied by the finding's own wording to check. (I did grep the corpus for other stray
all-caps tokens and stapled-sentence duplicates in docstrings and found none of this shape — the
remaining all-caps tokens in the tree are inside `#`-comments, which are explicitly exempt from the
rendering rules.) Given the finding names no other surface, I treat this as fully swept.

## Finding 2

**Verdict:** HONORED

**Evidence:** `src/DifferentialOperators.jl` module docstring. Diff hunk:
```
-operator is the exact term-by-term derivative of that trigonometric polynomial on the resolved band,
-the even-axis Nyquist term being zeroed (see the Nyquist split below), realized as a
-coefficientwise multiply by a wavenumber symbol with no finite-difference truncation. The wavenumber
+operator is the exact term-by-term derivative of that trigonometric polynomial on the resolved band —
+the band a grid's resolution actually represents, which excludes the Nyquist frequency of each
+even-length axis — realized as a coefficientwise multiply by a wavenumber symbol with no
+finite-difference truncation. The two symbol families treat that Nyquist term differently and
+deliberately so (see the Nyquist split below), so it is not simply zeroed everywhere. The wavenumber
```
The opening no longer claims each operator zeroes the even-axis Nyquist term; it now explicitly says
the two symbol families treat it differently and that it is "not simply zeroed everywhere," matching
the closing paragraph ("first-derivative wavenumbers are zeroed... while squared wavenumbers keep the
true squared wavenumber there"). Read current source `src/DifferentialOperators.jl:1-31` — the two
paragraphs now agree.

**class_surfaces:** The finding is specifically about the module docstring's own internal
self-contradiction (opening paragraph vs. closing paragraph, both within this one docstring) — it
does not name another module or another docstring carrying the same Nyquist-split claim. I grepped
`src/` for other module-docstring statements about the Nyquist split (`grep -n "Nyquist"
src/DifferentialOperators.jl`) and the remaining mentions (lines 96/184/201-202/253/1310-1332) are
all consistent with the corrected split and are not module-docstring-opening claims of the kind
flagged. No other surface is implied by the finding's own text.

## Finding 3

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `radial_kernel` docstring now reads in running prose: "Here `sigma`
is a function of one real argument... The `multipliers` are the [`FieldSpectralMultipliers`](@ref)
supplying `|k|^2`..." — no `The arguments are:` bulleted block remains (confirmed at
`src/Convolution.jl:330-348`). Diff shows the `- The arguments are:` bulleted block replaced by prose.

**class_surfaces:** The finding says "Rubric shape rule 1 requires running prose below three
arguments; inner(f, g) is the contrast case" and explicitly frames this as one instance of "Same
class as radial_kernel" shared with findings 4 and 5 (`spectral_cutoff`, `translation_kernel`). All
three sibling surfaces named by the finding set were checked directly (see Findings 4 and 5 below)
and all three were converted to prose in this same diff, so the class was swept as a set, not just
this one line.

## Finding 4

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `spectral_cutoff` docstring, `src/Convolution.jl:1471-1473`: "Here
`multipliers` is the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type and
array backend the kernel takes as its own, and `wavenumber_cutoff` is the cutoff wavenumber..." — the
former `The arguments are:` two-bullet block is gone. Diff confirms the bulleted block was removed
and replaced by the "Here `multipliers` is..." prose sentence.

**class_surfaces:** Named by the finding itself as "Same class as radial_kernel" — i.e. the class is
{`radial_kernel`, `spectral_cutoff`, `translation_kernel`} (findings 3/4/5). All three checked and
fixed identically in this diff (see Findings 3 and 5).

## Finding 5

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `translation_kernel` docstring, `src/Convolution.jl:1577-1579`:
"Here `multipliers` is the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element
type and array backend the kernel takes as its own, and `offset` is the displacement
`h = (h_1, h_2, h_3)`..." — the former `The arguments are:` bulleted block is gone. Diff hunk:
```
-The arguments are:
-- `multipliers` — the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type
-  and array backend the kernel takes as its own.
-- `offset` — the displacement ``h = (h_1, h_2, h_3)``, ...
+Here `multipliers` is the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type
+and array backend the kernel takes as its own, and `offset` is the displacement
+``h = (h_1, h_2, h_3)`` — ...
```

**class_surfaces:** Named by the finding itself as "Same class as radial_kernel" (the shared class
with findings 3/4). All three members of the class were located and confirmed fixed in this diff.

## Finding 6

**Verdict:** HONORED

**Evidence:** `src/Reductions.jl` `inner` docstring note, `src/Reductions.jl:767-772`. Diff hunk:
```
-!!! note "The mixed spectral pair allocates two correction planes"
+!!! note "The mixed spectral pair allocates one or two correction planes"
     In spectral representation `inner(f, f)` and `l2norm` run allocation-free, but the *mixed*
-    `inner(f, g)` materializes two ``O(N^2)`` correction planes — one folded-axis plane by the fiber,
-    twice. That is small beside the ``O(N^3)`` field, and it is paid per call, where `inner(f, f)` pays
+    `inner(f, g)` materializes ``O(N^2)`` correction planes — the folded axis's zero plane always, and
+    its Nyquist plane as well when that axis has even length, so an odd folded axis pays for one plane
+    and an even one for two. That is small beside the ``O(N^3)`` field, and it is paid per call, where `inner(f, f)` pays
```
The admonition title and body now correctly state the count is gated on `even_fold` (one plane for an
odd folded axis, two for even), matching the code (`src/Reductions.jl:875-901`, `even_fold =
iseven(...)`, `even_fold && (correction += ...)` appearing twice).

**class_surfaces:** The finding's own text is scoped to "inner's note" — it does not name a sibling
docstring making the same over-claim. I grepped the corpus (`docs/TESTING.md`, `docs/PERFORMANCE.md`,
`test/allocations.jl`) for other "correction plane(s)" mentions and none of them assert a fixed count
of "two" — they say "O(N²) correction planes" / "Parseval-correction planes" generically, which is not
the defect flagged (an unconditional "two"). No other surface is implied by the finding's own wording.

## Finding 7

**Verdict:** HONORED

**Evidence:** `src/Reductions.jl` `weighted_inner` docstring, `src/Reductions.jl:957-960`. Diff hunk:
```
 - `f`, `g` — two compatible, equal-order fields in spectral representation (`g = f` in the two-argument form).
+- `weights` — in the tuple form, a tuple of such kernels: every one is answered in a single traversal
+  and one device readback, bitwise-equal to calling the operation once per weight, and the results are
+  returned in the order given.
 - `w` — the weight: a spectral kernel in **any** of its storage classes, ...
```
The `weights` tuple-form parameter now has its own bullet in the signature-driven argument list,
alongside `f`, `g`, and `w`.

**class_surfaces:** The finding is narrowly about `weighted_inner`'s own signature having three
declared forms (`f, w`; `f, g, w`; `f, weights::Tuple`) with one parameter (`weights`) previously
undocumented in the bullets. It names no sibling operation with the same gap. No other tuple-taking
public operation in the reduction family (`radial_spectrum`, `radial_correlation`, etc.) takes a
tuple-of-kernels parameter of this shape, so there is no other surface the finding's wording implies.
