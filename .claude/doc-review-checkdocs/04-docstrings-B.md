# 04-docstrings-B — banked findings, /check-docs 2026-08-27

## Finding 1 — SeparableKernel docstring has two contradictory magnitude claims stapled together

**Location:** src/Convolution.jl SeparableKernel

**Why:** 'kilobytes rather than the 129 MiB' then 'roughly the megabytes a 256^3 kernel would take', plus an all-caps FIELD-SIZED artifact.

## Finding 2 — DifferentialOperators module docstring self-contradicts on Nyquist

**Location:** src/DifferentialOperators.jl module docstring

**Why:** Opening claims each operator zeroes the even-axis Nyquist term; the closing paragraph says squared wavenumbers keep the true value there.

## Finding 3 — radial_kernel uses the bulleted argument form with two positional args and no keyword

**Location:** src/Convolution.jl radial_kernel

**Why:** Rubric shape rule 1 requires running prose below three arguments; inner(f, g) is the contrast case.

## Finding 4 — spectral_cutoff uses the bulleted argument form with two positional args

**Location:** src/Convolution.jl spectral_cutoff

**Why:** Same class as radial_kernel.

## Finding 5 — translation_kernel uses the bulleted argument form with two positional args

**Location:** src/Convolution.jl translation_kernel

**Why:** Same class as radial_kernel.

## Finding 6 — inner's note claims the mixed spectral pair allocates two correction planes

**Location:** src/Reductions.jl inner

**Why:** The second plane is gated on even_fold, so an odd folded axis allocates one.

## Finding 7 — weighted_inner's tuple `weights` parameter is not bound in the argument list

**Location:** src/Reductions.jl weighted_inner

**Why:** Explained in prose but absent from the signature-driven bullets.

