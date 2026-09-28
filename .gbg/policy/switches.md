<!-- gbg:managed begin v2.0.0-rc.36 — rewritten by `gbg sync`; do not edit -->
# What GBGPeriodicFields has switched off

Each entry names a rule this package does not hold itself to, and why. A rule listed
here is read as the entry states it.

- `RULE.DOC.RETIRED_CLAIMS` — A decision log QUOTES a retired claim in order to record that it was retired: decision 20's entry says a kernel is itself a scalar field and is immediately followed by decision 60 superseding it. The ban and the log want opposite things from the same sentence, and the log is right. This is why the log is its own document: the rule can be narrowed to a FILE but not to a section, so splitting it turned an unfixable problem into a one-line switch. Every other rule still reads this file. (`docs/DECISIONS.md`)
- `RULE.API.POSITIONAL` — ONLY `Grid3D`'s two-argument constructor's `origin` keyword. It shifts every node, so the rule points the other way; the owner weighed that against the churn on 2026-09-02 and kept the keyword, the four-argument constructor taking it positionally. Every other argument in this file still follows the rule. (`src/Fields.jl`)
- `RULE.API.POSITIONAL` — ONLY the `array_type` keyword of the constructors that build a field by sampling a function. It picks the storage family the result lives in, not any value; making it positional would be an interface change breaking the consumer's calls for a consistency gain only. Owner-decided 2026-09-25 (finding 2026-09-24-documentation-review-01-009). Every other argument in this file still follows the rule. (`src/Fields.jl`)
- `RULE.API.POSITIONAL` — ONLY the callable field's `scheme` keyword, `field(x; scheme = …)`. A one-point convenience whose default is the usual case; owner-settled 2026-08-05, while `interpolate`/`anterpolate` keep `scheme` positional. Every other argument in this file still follows the rule. (`src/Interpolation.jl`)
- `RULE.API.POSITIONAL` — ONLY the `corrected` keyword of `var`, `std` and `cov`. These EXTEND `Statistics`, whose own methods spell it as a keyword; a positional form would break the drop-in standard-library use the package promises. Owner-decided 2026-09-25 (finding 2026-09-24-documentation-review-01-009). Every other argument in this file still follows the rule. (`src/Reductions.jl`)

<!-- gbg:managed end -->
