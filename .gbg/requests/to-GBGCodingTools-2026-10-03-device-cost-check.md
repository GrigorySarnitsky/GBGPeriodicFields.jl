Status: open — approved by the owner on 2026-10-03; sent to the GBGCodingTools session the same day.
Recorded in PF's `CLAUDE.md` (Planned directions) since 2026-09-30, when the owner ruled that the tool
is not extended with benchmarks yet; he has now asked for it to be raised.

# To GBGCodingTools: a check of a device operation against the memory it must move

## What is missing

No check in PF, in GBGHomogeneousTurbulence (HT) or in the tool asks whether an operation on a GPU runs
as fast as the memory it must move allows. The traffic audit the tool provides counts reads and writes,
on the CPU. A device operation can be at its counted minimum and still slow, because the extra cost is
computation, not traffic, and only a timing against the minimum traffic sees it.

## The case that showed it

`weighted_inner(f, w)`, the band-weighted spectral sum HT's forcing calls. HT's traffic audit found its
one-field form reading the field twice; a one-off timing script of HT's then put the whole device pass
40–60% above a plain read of the field on an RTX 5070 Ti. PF measured the parts at 256³ on a vector
field:

- **the double read** — traffic, which the audit caught. Fixed 2026-09-30; bitwise unchanged; the
  weighted reductions now have traffic-audit rows.
- **the band weight evaluated once per fiber component instead of once per mode** — +0.107 ms in
  `Float32`, +0.172 ms in `Float64`. Computation; the audit cannot see it. Not fixed.
- **per-element index arithmetic in the broadcast against the per-axis wavenumber arrays** — +0.059 ms in
  `Float32`, nothing measurable in `Float64`. Computation. Not fixed.

The last two wait for a check that would find and rank them. They are likely not alone: the same
shapes occur in `convolve!` and `combine!` with a radial kernel on a vector or tensor field, in
`laplacian!` and `inverse_laplacian!` on vector fields, and in the separable kernels' indexing.

## What is asked

A harness, in the shape of the existing audit contracts, that times a device operation, computes the
minimum bytes it must move (the traffic audit already knows them), divides by the card's measured
bandwidth, and reports the ratio, failing above a declared bound or at least ranking the operations.
The design, the bound, and how a timing on a shared machine is kept honest are the tool's to decide.

## Context the tool should know

- HT answered on 2026-09-30 that its timing was a one-off probe with no wiring to the tool.
- A timing needs an idle machine: PF's benchmark rule is that a run owns the host.
- PF has two GPU backends (CUDA, ROCm); a probe must work on both or record a skip on one.
