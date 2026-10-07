Status: open — approved by the owner on 2026-10-07; sent to the GBGCodingTools session the same day.

# To GBGCodingTools: a mirrored interface follows the interface it mirrors

When a package extends or deliberately mirrors another package's function, it follows that
interface's argument conventions, even where the rulebook's own conventions would say otherwise.

## The case that raised it

Applying rc.63's `RULE.API.POSITIONAL` to PF, every positional argument with a default became a
finding. Two of PF's cases are deliberate mirrors, and the owner ruled both stay as they are:

- **`anterpolate!`'s accumulate weights α and β**, positional with defaults 1 and 0, as in
  `LinearAlgebra.mul!(C, A, B, α, β)`. PF follows that convention package-wide (its invariant 10).
- **`lpnorm(f, p = 2)`**, as the standard library's `norm(x, p = 2)`.

The same reasoning already sits behind an earlier PF exception, now unnecessary: `var`, `std` and
`cov` take `corrected` as a keyword because `Statistics` does, so that PF's methods are drop-in
extensions of the standard ones.

## What is asked

A statement in the rulebook, and if it fits the rule's shape a recognised exception: where an
operation extends, or deliberately mirrors, a function of Base, a standard library or another
package, its arguments follow that function's conventions, and the rulebook's argument rules yield.
The mirrored interface is named where the operation is documented, so a reader can check the claim.
Without it, each such case needs a per-package switch restating the same reason.
