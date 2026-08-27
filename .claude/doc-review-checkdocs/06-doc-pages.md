# 06-doc-pages — banked findings, /check-docs 2026-08-27

## Finding 1 — api.md's Fields, Points and Interpolation entries are stale relative to index.md

**Location:** docs/src/api.md lines 9, 13, 14

**Why:** Missing decisions 73 (displace!/wrap!), 74 (family constructors), 75 (write_scheme/read_scheme).

## Finding 2 — reality_residual is undocumented on both overview pages

**Location:** docs/src/index.md, docs/src/api.md

**Why:** It has its own prose section on the Fields API page but appears in neither summary.

## Finding 3 — The tutorial builds a second, tensor-order-specific FieldTransformPlans

**Location:** docs/src/tutorial.md line 70

**Why:** Contradicts the FieldTransformPlans docstring, which says to build one per backend and element type but NOT per tensor order.

## Finding 4 — The examples' advect! hand-rolls point motion instead of using displace!/wrap!

**Location:** examples/HIST_CPU.jl:262, examples/gpu/rocm/HIST_ROCm.jl:291

**Why:** Lower confidence: decision 73 added the primitives for exactly this pattern; the demo claims to be written as a real consumer would.

