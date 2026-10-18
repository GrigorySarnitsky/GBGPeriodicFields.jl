<!-- gbg:managed begin v2.0.0-rc.83 — rewritten by `gbg sync`; do not edit -->
# What GBGPeriodicFields has switched off

Each entry names a rule this package does not hold itself to, and why. A rule listed
here is read as the entry states it.

- `RULE.API.POSITIONAL` — ONLY `RealFourierLayout(fft_dims = (1, 2, 3))`. A value type's constructor whose argument is the value itself, not an option of an operation: `RealFourierLayout((3, 1, 2))` names a layout as `Complex(1, 2)` names a number, and the zero-argument form names the standard layout. Owner-decided 2026-10-07. Every other argument in this file follows the rule. (`src/Fields.jl`)
- `RULE.DOC.RETIRED_CLAIMS` — A decision log QUOTES a retired claim in order to record that it was retired: decision 20's entry says a kernel is itself a scalar field and is immediately followed by decision 60 superseding it. The ban and the log want opposite things from the same sentence, and the log is right. This is why the log is its own document: the rule can be narrowed to a FILE but not to a section, so splitting it turned an unfixable problem into a one-line switch. Every other rule still reads this file. (`docs/DECISIONS.md`)

<!-- gbg:managed end -->
