Status: open — approved by the owner on 2026-10-07; sent to the GBGCodingTools session the same day.

# To GBGCodingTools: an optional argument whose type selects the method

`RULE.API.POSITIONAL` (rc.64) sorts arguments into two kinds: "any argument whose type selects the
method" is positional, and "every argument with a default" is a keyword. An argument can be both —
optional, and selecting the method by its type — and the rule does not say which clause decides. The
mirror clause and the switch are its only named exceptions, so these cases are now settled by a
session's judgement rather than by the rule.

## PF's cases

- **The transfer scheme** (PF decision 97). `interpolate(field, points[, scheme])`: the scheme's type
  selects the method (splines act on a field in physical representation, `DirectDFT` and `NUFFT` on one
  in spectral representation), and it defaulted to `CatmullRom`. The owner resolved it by removing the
  default, which takes it out of the overlap. That works where a required argument is sensible.
- **The exponent offset of `exponential_convolve!`** (decision 92).
  `exponential_convolve!(dest, f, mult, c[, offset_scale, offset][, α, β])`: the offset's type selects
  the method (a stored field or a `RadialKernel`), and it is optional; without it the factor has no
  offset term, which reads as a default of zero. Making it required is not sensible, most calls having
  no offset, so it cannot leave the overlap the way the scheme did.
- **A fused kernel** in `divergence!` and `helmholtz_projection!(dest, f, mult[, kernel][, α, β])`, and
  the **preserving scratch** in `to_physical!(physical, spectral, plans[, scratch])` (decision 64). Each
  is optional and type-dispatched. PF reads their absence as a different operation (no convolution
  fused; a transform free to consume its source), not as a default value, but the rule does not draw
  that line.

## What is asked

That the rule say how an optional, method-selecting argument is treated. One reading consistent with
the rule's own reason ("methods are dispatched on positional arguments alone, so what selects the
method must be one"): dispatch decides, and such an argument stays positional; "a default" means a
value filled in for an option, not the absence of an operation's optional term. The design is the
tool's; PF records its cases as judgement until the rule decides them.
