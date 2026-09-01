RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/api/FiberSections.md` shows the Internal API
  blurb rewritten from "the CPU-threading primitives and the fiberwise-algebra code generators, for
  anyone extending the package's algebra." to "the CPU-threading primitives, the fused fiberwise
  executor that every stamped operation runs through, the fiberwise-algebra code generators, the
  section-introspection helpers, and the storage-ownership check that keeps aliasing safe by
  construction, for anyone extending the package's algebra." — this names both families the finding
  said were missing (the fused fiberwise executor / decision 39 machinery, and the storage-ownership
  check `_check_owned_storage` / decision 59) plus the section-introspection helpers the finding also
  flagged as unnamed.
- **class_surfaces:** The finding's text is scoped to one site — `docs/src/api/FiberSections.md:36`,
  the Internal API blurb for the `FiberSections` module page — and does not name or imply any sibling
  surface (it is not an f/f! pair, not a convention repeated across pages). The banked file's own
  "Verified clean" section separately records that the sibling module blurbs (`FieldAlgebra`,
  `Fields`, `Points`, `Reductions`, `DifferentialOperators`) were already checked and match their
  blocks, so there is no unswept twin. Diff touches exactly this one file for this finding.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/api/Interpolation.md` shows the "in-kernel
  helpers" clause replaced with "the compatibility checks the transfer verbs route through" — matching
  the finding's evidence that the block holds `_check_nufft_compatibility` and
  `_check_transfer_colocation` (two compatibility checks), not in-kernel helpers, and matching the
  finding's own suggested fix verbatim in substance.
- **class_surfaces:** Scoped to one site — `docs/src/api/Interpolation.md:55`. Same reasoning as
  Finding 1: the finding names no other page or docstring carrying the same "in-kernel helpers"
  mischaracterization, and the file's "Verified clean" section covers the other module pages
  separately. No unswept surface implied by the finding's own text.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/api/Convolution.md` shows the blurb extended from
  six named entries to explicitly add "the exponential kernel pair — a device kernel and its gated CPU
  twin — that evaluates the mode factor once per mode rather than once per component," directly naming
  decision 79's `_exponential_convolution_modes!` / `_exponential_combination_modes!` pair the finding
  said was undocumented.
- **class_surfaces:** Scoped to one site — `docs/src/api/Convolution.md:83`. The finding names no
  sibling page with the same drift (it is specific to decision 79 landing after this blurb was
  written); the other module blurbs are separately verified clean in the same banked file. No unswept
  surface implied by the finding's own text.
