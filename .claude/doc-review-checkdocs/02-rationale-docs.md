# 02-rationale-docs — banked findings, /check-docs 2026-08-27

## Finding 1 — FORMALIZATION says FieldTransformPlans is determined by its tensor order

**Location:** docs/FORMALIZATION.md, Storage families

**Why:** Contradicted by decision 76; adapt_structure uses Val(0) witnesses.

## Finding 2 — No FORMALIZATION entry for reality_residual (decision 71)

**Location:** docs/FORMALIZATION.md

**Why:** A tested, nontrivial claim with no typed entry breaks the prose-formalization-test chain.

## Finding 3 — No FORMALIZATION entry for the tuple weighted_inner fusion identity (decision 72)

**Location:** docs/FORMALIZATION.md, weighted_inner

**Why:** Only the single-weight form is formalized; the tuple form's bitwise-equality identity is the class this page formalizes elsewhere.

## Finding 4 — TESTING §4 coverage-axes list has no entry for decision 76's component-offset alignment

**Location:** docs/TESTING.md §4

**Why:** A new admissible input region must get an axis row and a suite lane in the same change. TESTING mentions decision 76 nowhere.

## Finding 5 — No FORMALIZATION/TESTING mention of decisions 74 and 75

**Location:** docs/FORMALIZATION.md, docs/TESTING.md

**Why:** Lower confidence: the lane notes similar_field and write_field also have no entries, so the precedent for omission is consistent.

