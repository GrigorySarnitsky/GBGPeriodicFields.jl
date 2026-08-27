# 01-architecture — banked findings, /check-docs 2026-08-27

## Finding 1 — Decision 63 claims FieldTransformPlans carries R (its tensor order) as a type parameter

**Location:** docs/ARCHITECTURE.md §13 decision 63

**Why:** Decision 76 removed R. The struct has no R. Decision 63 carries no superseded-by note, unlike decisions 20/50/51/57/60.

## Finding 2 — Decision 49's spectral var formula omits the default Bessel correction

**Location:** docs/ARCHITECTURE.md §13 decision 49

**Why:** The displayed formula is the population moment, but var defaults to corrected = true and returns it scaled by N/(N-1).

