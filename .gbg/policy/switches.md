<!-- gbg:managed begin v2.0.0-rc.23 — rewritten by `gbg sync`; do not edit -->
# What GBGPeriodicFields has switched off

Each entry names a rule this package does not hold itself to, and why. A rule listed
here is read as the entry states it.

- `RULE.DOC.RETIRED_CLAIMS` — A decision log QUOTES a retired claim in order to record that it was retired: decision 20's entry says a kernel is itself a scalar field and is immediately followed by decision 60 superseding it. The ban and the log want opposite things from the same sentence, and the log is right. This is why the log is its own document: the rule can be narrowed to a FILE but not to a section, so splitting it turned an unfixable problem into a one-line switch. Every other rule still reads this file. (`docs/DECISIONS.md`)
- `RULE.TEX.CODE_SPAN_JULIA` — The notation page documents how the package's mathematics is SPELLED, and two of its rows exist to show LaTeX source: which delimiter commands to type (`\bigl`/`\Bigl`, never `\left`/`\right`) and why a table writes its bars as `\lvert…\rvert`. Set as math those names render as brackets and bars, and the reader loses the spelling the row is there to give. Owner-decided 2026-09-24 (finding 2026-09-24-documentation-review-01-107). Every other rule still reads this page. (`docs/src/notation.md`)

<!-- gbg:managed end -->
