<!-- gbg:managed begin v2.0.0-rc.4 — rewritten by `gbg sync`; do not edit -->
# What GBGPeriodicFields has switched off

Each entry names a rule this package does not hold itself to, and why. A rule listed
here is read as the entry states it.

- `RULE.TEX.MATHBF` — Deferred, not declined. The one bold string here is the wavenumber vector \
                         in the worked turbulence example, where italic k is the turbulent kinetic \
                         energy and the two would otherwise collide; the notation page states that \
                         and scopes it to the example. Declaring it is one line, and the owner is \
                         holding that line until the bold set can be settled together with \
                         GBGIsotropicTurbulence, whose notation this example follows. Declaring a \
                         set here first would make the fleet agree by coincidence rather than by \
                         decision. (the whole package)

<!-- gbg:managed end -->
