<!-- gbg:managed begin v2.0.0-rc.4 — rewritten by `gbg sync`; do not edit -->
# What GBGPeriodicFields has switched off

Each entry names a rule this package does not hold itself to, and why. A rule listed
here is read as the entry states it.

- `RULE.DOC.SHAPE` — These four are under a ratchet of this package's own — `lint_prose_shape` in \
                         docs/make.jl, whose committed baseline lets a unit shrink and never grow, \
                         where this rule caps a newcomer and then stops watching. The two are not \
                         redundant, they are INCOMPATIBLE: they disagree about whether a numbered \
                         item's own line belongs to its unit, so the rule reported 108 units the \
                         ratchet passes, and they share ONE file, docs/prose_shape.csv, so whichever \
                         re-baselines last leaves the other reading its numbers wrongly. This is an \
                         accommodation between two instruments, not a judgement that either is \
                         right: each was found wrong on one axis on 2026-09-18 — the ratchet \
                         dropped a line per numbered entry and both merged entries that restart \
                         numbering — and both were repaired the same day. The ratchet holds these \
                         four files for one reason: this package pins the tool at `:dev`, an \
                         absolute path on one machine, so the rule does not run on the second host \
                         or in CI, where the ratchet does. When the pin becomes a release, retiring \
                         `lint_prose_shape` and dropping this switch is the better end state. \
                         Everywhere else in the package this rule is on. (`docs/ARCHITECTURE.md`, `docs/FORMALIZATION.md`, `docs/TESTING.md`, `docs/PERFORMANCE.md`)
- `RULE.TEX.MATHBF` — Deferred, not declined. The one bold string here is the wavenumber vector \
                         in the worked turbulence example, where italic k is the turbulent kinetic \
                         energy and the two would otherwise collide; the notation page states that \
                         and scopes it to the example. Declaring it is one line, and the owner is \
                         holding that line until the bold set can be settled together with \
                         GBGIsotropicTurbulence, whose notation this example follows. Declaring a \
                         set here first would make the fleet agree by coincidence rather than by \
                         decision. (the whole package)

<!-- gbg:managed end -->
