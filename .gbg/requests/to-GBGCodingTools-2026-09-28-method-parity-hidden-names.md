Status: open, 2026-09-28. Filed by the GBGPeriodicFields session during the rc.37 upgrade. It blocks
PF's test suite on Julia 1.13 (the CI `'1'` lane) and nothing on 1.12; PF changes nothing meanwhile.

# `TestHarness.method_parity` counts compiler-generated functions on Julia 1.13

## What happens

On Julia 1.13.1 with 4 threads, PF's `test/method_parity.jl` fails every derived module count; on
1.12.7 it passes. Measured at PF's head with rc.37 in a copy with no manifests:

    Evaluated: 313 == 189    (Fields)       Evaluated: 202 == 117    (Convolution)
    Evaluated: 343 == 242    (Points)       Evaluated: 208 == 170, 367 == 274 (two more modules)

## Why

On 1.13, `names(mod; all = true)` also lists compiler-generated bindings named like `#809#val`, and
they own methods in the module. Measured in PF's `Fields`: 74 such names owning 129 methods on 1.13,
against 5 names owning 5 methods on 1.12. The difference, 124, is exactly the excess in the Fields
count (313 − 189). The counts for the other modules move the same way, though not all by exactly the
hidden-name total, so the engine may reach these methods by more than one route.

PF hit the same thing in its own dispatch-pair scan in `test/threading.jl` (19 pairs counted as 34 on
1.13) and fixed it there by skipping names that start with `#`, which are never a package's own
functions.

## What would settle it

Skip compiler-generated names (a leading `#`) wherever the engine enumerates a module's functions,
so a frozen count means the same on 1.12 and 1.13. The same enumeration may feed other harnesses
(`allocation_completeness`, `traffic_completeness`, `oracle_registry`); on 1.13 they passed in PF,
but a count of the surface would be worth checking there too.
