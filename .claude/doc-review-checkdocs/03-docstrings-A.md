# 03-docstrings-A — banked findings, /check-docs 2026-08-27

## Finding 1 — adapt's docstring says the plans carry their own tensor order

**Location:** src/Fields.jl, adapt docstring

**Why:** Contradicts the FieldTransformPlans docstring 100 lines earlier and decision 76.

## Finding 2 — FieldSpectralMultipliers' 'The fields are' list omits the six oriented views of decision 70

**Location:** src/Fields.jl, FieldSpectralMultipliers

**Why:** The struct stores twelve arrays; the docstring documents six.

## Finding 3 — Formula-like pseudo-code in backticks in the FiberSections codegen builders

**Location:** src/FiberSections.jl _vector_kernel_body, _fiberwise_pass!

**Why:** destination = alpha * formula + beta * destination is not well-formed Julia naming real identifiers.

