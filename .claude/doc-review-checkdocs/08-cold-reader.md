# 08-cold-reader — banked findings, /check-docs 2026-08-27

## Finding 1 — notation.md's |.| row is broken by literal pipes, inside the row warning about literal pipes

**Location:** docs/src/notation.md Operators table

**Why:** The rendered row truncates mid-sentence and the Code column shows a bare fragment.

## Finding 2 — FORMALIZATION uses unglossed differential-geometry vocabulary

**Location:** docs/FORMALIZATION.md Base-space motion

**Why:** trivialized tangent bundle, connection, exponential map, universal cover - none defined on the site.

## Finding 3 — 'deck group' is used once and never glossed

**Location:** docs/FORMALIZATION.md Statement 4

**Why:** Covering-space vocabulary; the plain meaning is whole-period lattice shifts.

## Finding 4 — assignment_window disambiguates 'assignment' using threading_cutoff from another page

**Location:** src/Convolution.jl assignment_window

**Why:** A reader landing on Convolution cold cannot resolve the aside.

## Finding 5 — 'the resolved band' is unglossed on the DifferentialOperators page

**Location:** src/DifferentialOperators.jl module docstring

**Why:** Defined only on the umbrella page, two pages earlier in the nav.

## Finding 6 — displace! uses 'the universal cover' without introducing it

**Location:** src/Points.jl displace!

**Why:** Covering-space term standing in for unwrapped coordinates.

## Finding 7 — 'the whole hierarchy' has no clear antecedent

**Location:** docs/src/api/Fields.md Spectral kernel protocol

**Why:** Could mean the four storage classes or the tensor orders.

