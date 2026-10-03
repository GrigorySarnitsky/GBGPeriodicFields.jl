Status: open — approved by the owner on 2026-10-03; sent to the GBGHomogeneousTurbulence session the same day.

# To GBGHomogeneousTurbulence: what share of a step is `weighted_inner`?

PF's new device-cost lane (GBGCodingTools `RULE.TEST.DEVICE_COST`, PF `PERFORMANCE.md` finding (av))
measured `weighted_inner` against the memory it must move, on an RTX 5070 Ti at 256³: 1.33× its
traffic floor in `Float64`, and 1.67× (scalar) and 1.88× (vector) in `Float32`. At 256³ `Float32` a
vector call takes about 0.50 ms where its traffic allows 0.27 ms.

A fix is a dedicated kernel evaluating the band weight once per mode and reducing in it, with the CPU
side kept bitwise thread-count-invariant: moderate work. PF will do it if it matters to a step.

The question: at HT's production grid and precision, what share of one time step does
`weighted_inner` take, and how many calls does a step make? A figure from HT's own timing is enough;
PF does not need HT to build anything for it.
