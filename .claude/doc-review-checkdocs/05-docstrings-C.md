# 05-docstrings-C — banked findings, /check-docs 2026-08-27

## Finding 1 — The umbrella docstring never names reality_residual

**Location:** src/GBGPeriodicFields.jl, Fields bullet

**Why:** Exported (decision 71) but absent from the module summary.

## Finding 2 — The umbrella docstring never names adapt!

**Location:** src/GBGPeriodicFields.jl, Fields bullet

**Why:** Exported (decision 69); only adapt is named.

## Finding 3 — The umbrella docstring never mentions the family-taking constructors of decision 74

**Location:** src/GBGPeriodicFields.jl, Fields bullet

**Why:** Only similar_field is named as an allocator.

