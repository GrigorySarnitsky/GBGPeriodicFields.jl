# Documentation Review — 2026-09-24-documentation-review-01

!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

Run `2026-09-24-documentation-review-01` of `GBGPeriodicFields`, by GBGCodingTools dev, from commit `2b20a57a`.

**The owner stopped it.** It launched 285 agent(s), with the bound readers, and made 2 of 4 fix pass(es).

!!! warning "Readers that wrote nothing"
    3 agent(s) wrote nothing readable, even launched a second time: verify-2026-09-24-documentation-review-01-046, verify-2026-09-24-documentation-review-01-052, verify-2026-09-24-documentation-review-01-115. What they were to judge was not judged.

## 40 finding(s) were thrown away

The owner stopped this run. What its readers reported and nobody had yet stood behind
was dropped and is not written down here; what follows is only what had been fixed and
verified before the stop.

## Findings — 80

### 2026-09-24-documentation-review-01-002  inverse_curl's docstring says that curl∘inverse_curl reproduces a divergence-free field 'exactly at every mode', but that identity fails wherever the derivative wavenumber a vanishes at a nonzero k (the pure-Nyquist corners of an all-even grid): there |a|^2 = 0, the kernel writes zero, and a field that is discretely divergence-free there (a·ŵ = 0 trivially) comes back as zero. The warning names only the k = 0 mode as having no preimage. The continuum identity is kept on every mode with a ≠ 0, not on every mode.

Reported by `differential_geometry`, decided by an agent.

**Fix.** Scope the claim to every mode with a ≠ 0, and extend the warning to the modes where the whole derivative wavenumber vanishes (k = 0 and the pure-Nyquist corners), both written zero — matching how helmholtz_projection! already names 'the pure-Nyquist corners where the whole derivative wavenumber vanishes'.

- `src/DifferentialOperators.jl`:1196  (inverse_curl!)
- `src/DifferentialOperators.jl`:1182  (inverse_curl!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`

### 2026-09-24-documentation-review-01-004  The pullback–pushforward adjunction is written with the grid inner product on a measure: ARCHITECTURE states that ι_* q lands in MEASURES, then writes the adjunction as ⟨f, ι_* q⟩_grid, where ⟨·,·⟩_grid was defined two displays earlier as (1/|Ω|)∫ f·g dx between sections. Paired with a measure, the natural reading carries that 1/|Ω| and the equality then fails unless |Ω| = 1; the identity that holds is the canonical function–measure duality ∫ f d(ι_* q). The identification with a section (density with respect to the normalized grid measure) is stated afterwards, so the display uses the identification before its hypothesis is in place.

Reported by `differential_geometry`, decided by an agent.

**Fix.** Write the adjunction with the duality pairing, ⟨ι* f, q⟩_pts = ∫_Ω f d(ι_* q), and keep ⟨·,·⟩_grid for the density form ⟨f, (N/M) W^T q⟩_grid once the regularization and density steps are stated.

- `docs/ARCHITECTURE.md`:880  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:874  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))

### 2026-09-24-documentation-review-01-005  ARCHITECTURE section 10 states ⟨f,g⟩_grid = (1/|Ω|)∫ f·g dx = (1/N)Σ_x f·g without qualification and says 'exactly as the package's inner computes them'. The continuum-integral equality holds only when the product f·g is resolved; it fails at Nyquist content, e.g. the sampled (−1)^n has trigonometric interpolant cos(πx/Δx), whose continuum mean square is 1/2 while the discrete mean is 1. The inner docstring in src/Reductions.jl carries exactly that qualifier ('exact when the product f·g is resolved ... under aliasing the discrete sum is the definition'); the rationale page does not, so the two pages state the grid measure's relation to the continuum differently.

Reported by `differential_geometry`, decided by an agent.

**Fix.** Add the Reductions qualifier: the continuum form equals the discrete sum when f·g is resolved on the grid, and otherwise the discrete sum is the definition.

- `docs/ARCHITECTURE.md`:835  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:840  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `97966207`)

### 2026-09-24-documentation-review-01-006  Module docstrings are not maps. Several carry formulas that belong in the operation homes (RULE.DOC.TWO_TIER too), and two put a glossary or an admonition between the identity and the contents list, where the order should be identity, list, then an optional trailing remark.

Rule: `RULE.DOC.MODULE_MAP`.  
Reported by `full`, decided by an agent.

Interpolation's module docstring carries a display ```math block (the M<Wf,q> = N<f,W^T q> adjoint identity) and the inline (Wf)_p = f(x_p). Reductions' map writes R_{ij} = <u'_i u'_j>, FieldAlgebra's writes alpha a + beta b, and DifferentialOperators' writes the rate (1/2) curl u. On ordering: GBGPeriodicFields has a six-bullet glossary and a 'Scalar, vector and second-order tensors only' note before its list, and Reductions puts a note between 'The parts are, ...' and its bullet list.

**Fix.** Move the adjoint identity and the (Wf)_p definition into the interpolate!/anterpolate! homes, the covariance formula into cov, and the combination formula into combine!, keeping only the linked one-liners in the maps. Move the umbrella's R <= 2 note and the Reductions Statistics note after the lists, as trailing remarks.

- `src/Interpolation.jl`:22  (Interpolation)
- `src/Interpolation.jl`:10  (Interpolation)
- `src/Reductions.jl`:36  (Reductions)
- `src/FieldAlgebra.jl`:24  (FieldAlgebra)
- `src/DifferentialOperators.jl`:21  (DifferentialOperators)
- `src/GBGPeriodicFields.jl`:51  (GBGPeriodicFields)
- `src/Reductions.jl`:21  (Reductions)
- `docs/ARCHITECTURE.md`:870  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `src/Reductions.jl`:666  (cov)
- `src/Convolution.jl`:1556  (exponential_convolve!)
- `src/FieldAlgebra.jl`:519  (combine!)
- `src/FieldAlgebra.jl`:525  (combine!)
- `src/FieldAlgebra.jl`:525  (combine!)
- `src/FieldAlgebra.jl`:555  (combine!)
- `src/FieldAlgebra.jl`:537  (combine!)

### 2026-09-24-documentation-review-01-009  Some keyword arguments change the result, and no Switch in .gbg/config.jl covers them. The corrected keyword of var/std/cov changes the returned number. The array_type keyword of the function-initialized field constructors picks the storage family, which the family constructors take positionally. Grid3D's origin keyword and the callable field's scheme keyword are owner-settled exceptions in CLAUDE.md, but they are not declared as Switches either, which is the only form of exception the rule recognizes.

Rule: `RULE.API.POSITIONAL`.  
Reported by `full`, decided by an agent.

Reductions.jl: var/std/cov(...; corrected::Bool = true) switches the divisor between N and N-1. Fields.jl: ScalarFieldPhysical(f, grid, layout; array_type = Array), while the family constructor is ScalarFieldPhysical(family::Type{<:AbstractArray}, grid, layout). Grid3D(grid_size, domain_size; origin = ...) shifts every node. (field)(x; scheme = CatmullRom) changes the interpolant. .gbg/config.jl declares a Switch only for RULE.DOC.RETIRED_CLAIMS.

**Fix.** Declare Switches on RULE.API.POSITIONAL, each with its reason: the settled origin and scheme keywords, plus corrected (mirroring Statistics) if the owner agrees. Make array_type positional to match the family constructors, or switch it too.

!!! warning "The code may be what is wrong"
    The reader believed the documentation and the code disagree, and that the code is the wrong half. That is a question for the owner, not a documentation fix.

- `src/Reductions.jl`:547  (Reductions)
- `src/Reductions.jl`:584  (Reductions)
- `src/Reductions.jl`:664  (cov)
- `src/Fields.jl`:422  (ScalarFieldPhysical)
- `src/Fields.jl`:133  (Grid3D)
- `src/Interpolation.jl`:1173  (field::AbstractFieldPhysical)
- `src/Fields.jl`:564  (VectorFieldPhysical)
- `src/Fields.jl`:721  (TensorFieldPhysical)

### 2026-09-24-documentation-review-01-010  Some docstrings use symbols that the notation page assigns elsewhere. They index grid and point sums with n and i where the page fixes sum_x over grid points and sum_p (f_p) over points, i being a fiber index. They write the base average as \bar f where the page fixes <f>. translation_kernel writes the derivative wavenumber as \tilde k_a where the page names it a. weighted_inner uses w both as the mode multiplier and as a physical convolution kernel (w ⋆ g). The architecture document calls the field s where the page's symbol is f.

Rule: `RULE.DOC.ONE_NOTATION`.  
Reported by `full`, decided by an agent.

docs/src/notation.md fixes Summations as sum_x over the N grid points, sum_p over the M points and sum_k over modes. It lists i, j, k as fiber indices, <.> as the base average, a as the derivative wavenumber vector, w as a multiplier weighting an inner product mode by mode, and f, g as a field. The sites below each use another symbol for one of these concepts, or reuse one of these symbols for another concept.

**Fix.** Rewrite the mean, var and lpnorm formulas with sum_x f(x) and sum_p f_p, and <f> in place of \bar f. In translation_kernel, use a_a or add a notation-page entry for \tilde k. In weighted_inner, write the physical side with a named kernel whose transfer function is w, or state once that w also names that kernel. In ARCHITECTURE §2, use f in place of s.

- `src/Reductions.jl`:1559  (lpnorm)
- `src/Reductions.jl`:535  (Reductions)
- `src/Reductions.jl`:552  (Reductions)
- `src/DifferentialOperators.jl`:1410  (inverse_laplacian!)
- `src/Convolution.jl`:1906  (translation_kernel)
- `src/Reductions.jl`:1009  (weighted_inner)
- `docs/ARCHITECTURE.md`:182  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / The architecture map)
- `src/Convolution.jl`:1906  (translation_kernel)
- `src/Convolution.jl`:1903  (translation_kernel)

### 2026-09-24-documentation-review-01-011  The radial_spectrum docstring is off by one against the code. It says spectrum[i] holds the modes with round(|k|/Δk) = i, but the returned vectors are 1-based: spectrum[1] is the κ = 0 shell, and in general spectrum[i] holds round(|k|/Δk) = i - 1.

Rule: `RULE.DOC.VERIFIED`.  
Reported by `full`, decided by an agent.

Reductions.jl _spectral_shell_bin_kernel!: shell = round(Int, sqrt(squared)/fundamental), then Atomix.@atomic value_bins[shell + 1] += .... _radial_spectrum_bin returns shells = T.(0:(number_of_shells - 1)) .* fundamental. So spectrum[i] pairs with shells[i] = (i-1)Δk. The docstring's own later sentence, 'shell m collects |k| within ±Δk/2 of mΔk', is 0-based, so it contradicts the spectrum[i] sentence beside it.

**Fix.** State that spectrum[i] is the shell centred on shells[i] = (i-1)Δk, or index the formula by m = i - 1.

- `src/Reductions.jl`:1320  (radial_spectrum)
- `src/Reductions.jl`:1325  (radial_spectrum)

### 2026-09-24-documentation-review-01-012  inverse_curl! claims too much. Its docstring says curl(inverse_curl) reproduces a divergence-free field 'exactly at every mode', and that only the k = 0 mode is set to zero. The code also zeroes every Nyquist-corner mode where all three derivative wavenumbers vanish, e.g. k = (N/2, 0, 0) on an even axis, and at such a mode a nonzero ŵ is discretely divergence-free.

Rule: `RULE.DOC.VERIFIED`.  
Reported by `full`, decided by an agent.

_inverse_curl_kernel!/_inverse_curl_modes!: squared = sum of derivative-wavenumber squares; reciprocal = ifelse(iszero(squared), 0, inv(squared)). The derivative family a is zeroed at an even axis's Nyquist frequency, so at a mode whose every component is 0 or Nyquist, a = 0 and the output is 0. Expanding: curl(i a × ŵ/|a|^2) = ŵ - a(a·ŵ)/|a|^2 holds only where |a| ≠ 0. Where a = 0, a·ŵ = 0 for any ŵ, so a nonzero divergence-free input maps to 0 and is not reproduced.

**Fix.** Scope the claim ('at every mode with a ≠ 0') and extend the warning: the zero mode, and each Nyquist-corner mode where a vanishes, is written zero.

- `src/DifferentialOperators.jl`:1196  (inverse_curl!)
- `src/DifferentialOperators.jl`:1194  (inverse_curl!)
- `src/DifferentialOperators.jl`:1181  (inverse_curl!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `ccb0fe40`)

### 2026-09-24-documentation-review-01-013  Two prose statements about behaviour do not match the code. The tutorial names anterpolate and radial_spectrum as the only atomic, run-to-run-varying operations, but radial_correlation also bins with Atomix scatter-adds. embed_modes!'s identity says it 'Add[s]' the coarse modes, but its default (β = 0) overwrites them.

Rule: `RULE.DOC.VERIFIED`.  
Reported by `full`, decided by an agent.

Reductions.jl _physical_shell_bin_kernel! (used by radial_correlation) does Atomix.@atomic value_bins[shell + 1] += accumulated, a floating-point atomic accumulation, so its summation order is nondeterministic like radial_spectrum's. Fields.jl: embed_modes!(destination, source) = _shared_modes!(destination, source, Val(true), 1, 0), and its β bullet says '0 by default, which overwrites them'.

**Fix.** Add radial_correlation to the tutorial's list of the exceptions (write 'the radial reductions'). Reword embed_modes!'s identity as 'Write (or, with β ≠ 0, add) a coarser field's modes into ...'.

- `docs/src/tutorial.md`:196  (Getting started / Running multithreaded)
- `src/Fields.jl`:3118  (embed_modes!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `8e5ccd7d`)

### 2026-09-24-documentation-review-01-016  Rendered code blocks that scroll sideways on a desktop page: each has one or more lines of 95-114 characters, while the 816 px column holds about 90 (about 87 inside a docstring). Measured natural widths are 826-986 px against boxes of 756-812 px.

Rule: `RULE.TEX.NO_HSCROLL`.  
Reported by `rendered`, decided by an agent.

Headless Chromium measurement: api/Fields 784/826 px, api/Reductions 756/834, tutorial 812/927, 812/986, 812/918, hist_cpu 812/986, 812/868, 812/834, 812/868, 812/960.

**Fix.** Hand-wrap each line to 88 columns or fewer. Move long trailing comments onto their own line above the code, and break long calls after a comma with a hanging indent.

!!! warning "The code may be what is wrong"
    The reader believed the documentation and the code disagree, and that the code is the wrong half. That is a question for the owner, not a documentation fix.

- `src/Fields.jl`:2462  (Fields)
- `src/Reductions.jl`:1355  (radial_spectrum)
- `src/Reductions.jl`:1355  (radial_spectrum)
- `docs/src/tutorial.md`:54  (Getting started / Representations: physical ↔ spectral)
- `docs/src/tutorial.md`:74  (Getting started / Differential operators)
- `docs/src/tutorial.md`:129  (Getting started / Fiberwise algebra and L²/measure reductions)
- `examples/HIST_CPU.jl`:50
- `examples/HIST_CPU.jl`:50
- `examples/HIST_CPU.jl`:142  (make_workspace)
- `examples/HIST_CPU.jl`:142  (make_workspace)
- `examples/HIST_CPU.jl`:256  (step!)
- `examples/HIST_CPU.jl`:319  (run_hist)
- `examples/HIST_CPU.jl`:394  (run_hist)
- `examples/HIST_CPU.jl`:394  (run_hist)
- `examples/gpu/rocm/HIST_ROCm.jl`:276  (step!)

### 2026-09-24-documentation-review-01-017  Display formulas set several equations side by side on one rendered line behind \quad/\qquad, which the rule forbids by name. They fit at desktop width today, but they are the packed form the rule exists to prevent.

Rule: `RULE.TEX.NO_HSCROLL`.  
Reported by `rendered`, decided by an agent.

In the cross! docstring, the three component equations share one gathered row, joined by \quad. In l2norm, the Grid3D and PointSet formulas share one line, separated by \qquad.

**Fix.** Give each equation its own row of the gathered/aligned environment (end each row with \\).

- `src/FieldAlgebra.jl`:1015  (cross!)
- `src/Reductions.jl`:930  (l2norm)

### 2026-09-24-documentation-review-01-018  Display formulas were wrapped in the source by a bare line break, with no aligned or gathered environment. KaTeX reads a newline as a space, so each one renders as a single long line and the wrap the author wrote is lost. In the reality_projection! docstring, two separate assignments merge into one line. They fit the desktop column now; they do not fit narrower screens.

Rule: `RULE.TEX.NO_HSCROLL`.  
Reported by `rendered`, decided by an agent.

In the extracted HTML these blocks contain '\n' with no \begin{...}, and the rendered KaTeX shows each on one row.

**Fix.** Wrap each one in \begin{aligned}...\end{aligned} with an explicit \\ and & alignment at the intended break.

- `src/Fields.jl`:2829  (reality_projection!)
- `src/Convolution.jl`:1580  (exponential_convolve!)
- `src/DifferentialOperators.jl`:929  (divergence!)
- `src/DifferentialOperators.jl`:1540  (helmholtz_projection!)
- `src/DifferentialOperators.jl`:1519  (helmholtz_projection!)
- `src/Reductions.jl`:1010  (weighted_inner)

### 2026-09-24-documentation-review-01-020  Several symbols appear in docstrings that never bind them: R (tensor order) in the builders, nu/p/tau in the hyperviscous example, m in the spline-family aside, alpha/beta in the module map, and sigma_1..sigma_3 in the separable internal (sigma otherwise names the radial symbol).

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Convolution`, decided by an agent.

radial_kernel, spectral_cutoff and spectral_band each say 'an R >= 1 field' with no clause saying R is the tensor order; p and tau are not standard; m is never introduced; sigma_a is not bound and collides with the radial sigma.

**Fix.** Add a binding clause at each first use (R the tensor order, nu the viscosity, p the hyperviscous power, tau a time step, m the smoothness index, the separable factors as g_a) or drop the symbol.

- `src/Convolution.jl`:360  (radial_kernel)
- `src/Convolution.jl`:283  (RadialKernel)
- `src/Convolution.jl`:1814  (assignment_window)
- `src/Convolution.jl`:30  (Convolution)
- `src/Convolution.jl`:786  (_apply_separable_convolution!)
- `src/Convolution.jl`:804  (_separable_convolution_pass!)
- `src/Convolution.jl`:825  (Convolution)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `5be08fdb`)

### 2026-09-24-documentation-review-01-022  'Base' is used as a package term (the grid the field lives on) without definition.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Convolution`, decided by an agent.

Only the SeparableKernel field list glosses 'the base and Fourier layout', and that comes after the first use; a cold reader cannot tell 'base' means the grid.

**Fix.** Say 'grid' or define base as the grid the field is sampled on at first use.

- `src/Convolution.jl`:468  (SeparableKernel)
- `src/Convolution.jl`:468  (SeparableKernel)
- `src/Convolution.jl`:615  (materialize_kernel)
- pass 1: blind verifier `FIXED`, with the diff `LINE_ONLY`  (commit `44c5420d`)
- pass 2: blind verifier `FIXED`, with the diff `FIXED`  (commit `44c5420d`)

### 2026-09-24-documentation-review-01-025  The 'trailing kernel of a fused operator' and 'kernel-composed arities' refer to package operations the page never explains.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Convolution`, decided by an agent.

No clause says that some differential operators accept a kernel as a last argument and apply it in the same pass; 'arity' used for an extra method is jargon.

**Fix.** Name them once: 'the differential operators `divergence!` and `helmholtz_projection!`, which accept a kernel as a trailing argument and apply it in the same pass'.

- `src/Convolution.jl`:470  (SeparableKernel)
- `src/Convolution.jl`:1593  (exponential_convolve!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `39b68e32`)

### 2026-09-24-documentation-review-01-026  Benchmark jargon ('CPU lanes', 'one card', 'the other') quotes measurements over unnamed configurations.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Convolution`, decided by an agent.

A reader cannot tell what a 'lane' is (a thread count? a host?) or which GPU 'one card' and 'the other' are, so the figures cannot be applied.

**Fix.** Say what a lane is (thread counts on the tested CPUs) and name the two GPUs, or state the figures without the lab shorthand.

- `src/Convolution.jl`:314  (RadialKernel)
- `src/Convolution.jl`:318  (RadialKernel)
- `src/Convolution.jl`:624  (materialize_kernel)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `728331e4`)

### 2026-09-24-documentation-review-01-027  A label-with-colon fragment and a verbless sentence state the representation restriction.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Convolution`, decided by an agent.

'Spectral representation only' has no subject or verb; in exponential_convolve! it stands as a whole sentence.

**Fix.** Write 'The operation is defined only in spectral representation.'

- `src/Convolution.jl`:960  (convolve!)
- `src/Convolution.jl`:1522  (exponential_convolve!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `ee152d5a`)

### 2026-09-24-documentation-review-01-028  The StoredKernel method of materialize_kernel does not say what it returns.

Rule: `RULE.DOC.RETURNS`.  
Reported by `withheld@api-Convolution`, decided by an agent.

Its siblings name the returned StoredKernel; this identity sentence names only 'the result' and there is no arrow or Returns sentence.

**Fix.** Say 'Return a copy of the kernel as a new StoredKernel, owning storage no other kernel shares.'

- `src/Convolution.jl`:250  (materialize_kernel)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `d3b7abf3`)

### 2026-09-24-documentation-review-01-030  The domain symbol Omega is used in integrals but bound nowhere on the page.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-DifferentialOperators`, decided by an agent.

inverse_laplacian! writes \int_\Omega f dx = 0 with only 'on a periodic box' nearby; no clause says Omega is the periodic box.

**Fix.** Bind it in the sentence: 'on a periodic box \Omega the system is solvable only when ...'.

- `src/DifferentialOperators.jl`:1399  (inverse_laplacian!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `21b18fe8`)

### 2026-09-24-documentation-review-01-032  The Internal API mutators never state what they return: none carries an arrow and none has a 'Returns ...' sentence, and their identity sentences ('Run ...', 'Apply ...') do not name a result.

Rule: `RULE.DOC.RETURNS`.  
Reported by `withheld@api-DifferentialOperators`, decided by an agent.

_apply_helmholtz_projection!, _apply_spectral_divergence!, _apply_spectral_inverse_laplacian!, _apply_spectral_laplacian!, _curl_modes!, _helmholtz_projection_modes!, _inverse_curl_modes!, _scalar_gradient_modes!, _symmetric_gradient_modes!, _vector_gradient_modes! (only _optional_kernel_value says what it returns).

**Fix.** Add one 'Returns destination.' / 'Returns nothing.' sentence to each, before any caveat.

- `src/DifferentialOperators.jl`:314  (_apply_helmholtz_projection!)
- `src/DifferentialOperators.jl`:535  (_curl_modes!)
- `src/DifferentialOperators.jl`:147  (_apply_spectral_laplacian!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `e622a098`)

### 2026-09-24-documentation-review-01-033  A backtick span holds an index list ending in an ellipsis, which is not well-formed Julia.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@api-DifferentialOperators`, decided by an agent.

The span contains a trailing '…', so it names no expression; it is an ordering description, which belongs in prose or LaTeX.

**Fix.** Write the order as math, e.g. $(1,1), (1,2), (1,3), (2,1), \dots$, or in words ('row-major: the first row, then the second').

- `src/DifferentialOperators.jl`:453  (_vector_gradient_modes!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `8072d54f`)

### 2026-09-24-documentation-review-01-035  Function docstrings whose identity sentence does not name a result, and whose signature carries no arrow, never say what the call returns: the public with_threading (does it return f()'s value?), the in-place helpers, and three accessors phrased as statements rather than returns.

Rule: `RULE.DOC.RETURNS`.  
Reported by `withheld@api-FiberSections`, decided by an agent.

with_threading says only "Run `f()` with ..."; _assign!, _fiberwise_pass!, _write_values!, _accumulate_values!, _assign_slabs!, _foreach_outer_slab describe effects only; _fiber_order, _fiber_type and _section_tensor_order describe a value without saying it is returned.

**Fix.** Add a 'Returns ...' sentence before any caveat (e.g. "Returns the value of `f()`.", "Returns `destination`.", "Returns `nothing`."), or rephrase the accessors as "Return the ...".

- `src/FiberSections.jl`:167  (with_threading)
- `src/FiberSections.jl`:279  (_assign!)
- `src/FiberSections.jl`:803  (_fiberwise_pass!)
- `src/FiberSections.jl`:760  (_write_values!)
- `src/FiberSections.jl`:1135  (_fiber_order)
- `src/FiberSections.jl`:1123  (_fiber_type)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `59dc11f8`)

### 2026-09-24-documentation-review-01-037  The three norm builders state a formula in a symbol their docstring never binds: the argument is `symbol`, but the formulas use φ, u and A with no clause tying them to it (their siblings _det_tensor_rhs and _trace_tensor_rhs do bind A as 'the tensor `symbol`').

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-FiberSections`, decided by an agent.

_norm_scalar_rhs(symbol) writes |φ|, _norm_vector_rhs(symbol, kind) writes u_i, _norm_tensor_rhs(symbol, kind) writes A_ij; none of φ, u, A is introduced.

**Fix.** Bind the symbol as the siblings do: 'the pointwise absolute value |φ| of the scalar `symbol`', 'the Euclidean norm of the vector `symbol` (u)', 'the Frobenius norm of the tensor `symbol` (A)'.

- `src/FiberSections.jl`:662  (_norm_scalar_rhs)
- `src/FiberSections.jl`:670  (_norm_vector_rhs)
- `src/FiberSections.jl`:679  (_norm_tensor_rhs)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `6a8d444d`)

### 2026-09-24-documentation-review-01-038  Three backtick spans are not well-formed Julia because they carry a prose ellipsis ('…' or a bare '...') as a placeholder.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@api-FiberSections`, decided by an agent.

`term_1 .+ term_2 .+ …`, `reshape(view(flat, 2:end), …)` and `Base.Broadcast.broadcasted(...)` do not parse; '…' is not a Julia token and a lone '...' is not a valid argument.

**Fix.** Write concrete Julia (`term_1 .+ term_2 .+ term_3`, `reshape(view(flat, 2:end), dims)`, `Base.Broadcast.broadcasted(f, args...)`) or move the ellipsis outside the code span.

!!! warning "The code may be what is wrong"
    The reader believed the documentation and the code disagree, and that the code is the wrong half. That is a question for the owner, not a documentation fix.

- `src/FiberSections.jl`:475  (_sum_terms)
- `src/FiberSections.jl`:113  (_check_owned_storage)
- `src/FiberSections.jl`:407  (_to_broadcasted)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `11366004`)

### 2026-09-24-documentation-review-01-039  The module docstring uses 'fiber-constant' (and 'point-values') before the paragraph that defines fiber, base and section; a cold reader meets the term undefined.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-FieldAlgebra`, decided by an agent.

Paragraph 2 says 'a factor held fiber-constant'; only paragraph 3 ('Three words recur below ... A fiber is the value at one base point') defines fiber.

**Fix.** Move the three-word definition paragraph ahead of the representation paragraph, or gloss 'fiber-constant' as 'the same value at every grid point' where it is used.

- `src/FieldAlgebra.jl`:12  (FieldAlgebra)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `c6147d69`)

### 2026-09-24-documentation-review-01-042  Verbless fragments stand as sentences: 'Physical-space representation only.' and 'Physical representation only.', and the colon-tag lead-ins 'Pointwise over the base:' before each display formula.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-FieldAlgebra`, decided by an agent.

None of these has a verb; the lead-ins are label-colon tags.

**Fix.** Write 'It is defined in physical representation only.' and 'Pointwise over the base, the components are:' / 'At every grid point it computes:'.

- `src/FieldAlgebra.jl`:1534  (FieldAlgebra)
- `src/FieldAlgebra.jl`:1426  (FieldAlgebra)
- `src/FieldAlgebra.jl`:907  (dot!)
- `src/FieldAlgebra.jl`:1350  (FieldAlgebra)
- `src/FieldAlgebra.jl`:1133  (FieldAlgebra)
- `src/FieldAlgebra.jl`:1574  (sym!)
- `src/FieldAlgebra.jl`:1603  (skew!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `b7f09f70`)

### 2026-09-24-documentation-review-01-043  The mutator map! never says what it returns; its identity sentence says it writes into destination but no 'returns destination' sentence follows, unlike every other in-place form on the page.

Rule: `RULE.DOC.RETURNS`.  
Reported by `withheld@api-FieldAlgebra`, decided by an agent.

The map! docstring has no 'return' statement; its signature has no arrow.

**Fix.** Add ', and return `destination`' to the identity sentence.

- `src/FieldAlgebra.jl`:1806  (map!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `a49570e2`)

### 2026-09-24-documentation-review-01-044  The page cites numbered invariants and decisions, and points to comments and loops 'above'/'below' in the source, none of which a reader of this page can see; the reference carries no meaning on the page.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Fields`, decided by an agent.

Nothing on the page says what invariant 5, 14, 2 or 3, or decision 70 or 76, is; 'the module comment above' and 'the gated slab-threaded loop below' refer to source the rendered page does not show; a repo test path is cited as if the reader knew it.

**Fix.** State the content the number stands for in a clause (e.g. 'the Nyquist zeroing described below'), and drop the decision numbers and positional source references from rendered docstrings.

- `src/Fields.jl`:1755  (FieldSpectralMultipliers)
- `src/Fields.jl`:1789  (FieldSpectralMultipliers)
- `src/Fields.jl`:2452  (Fields)
- `src/Fields.jl`:908  (_check_family_element_type)
- `src/Fields.jl`:1433  (_component_view)
- `src/Fields.jl`:2926  (_shared_mode_index)
- `src/Fields.jl`:3003  (_shared_modes_pass!)
- `src/DifferentialOperators.jl`:381  (_scalar_gradient_modes!)
- `src/DifferentialOperators.jl`:453  (_vector_gradient_modes!)
- `src/DifferentialOperators.jl`:807  (gradient!)
- `src/DifferentialOperators.jl`:808  (gradient!)
- `src/DifferentialOperators.jl`:1109  (curl!)
- `src/DifferentialOperators.jl`:1191  (inverse_curl!)
- `src/DifferentialOperators.jl`:1267  (symmetric_gradient!)
- `src/Fields.jl`:1757  (FieldSpectralMultipliers)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `8831558a`)

### 2026-09-24-documentation-review-01-048  Several internal docstrings open with a verbless noun phrase instead of a sentence.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Fields`, decided by an agent.

Each quoted opener has no main verb: it names the result but never says the function returns or is it.

**Fix.** Lead with a verb: 'Return the base an object was built for.', 'Return the linear index pair ...', 'Hold the shared body ...' etc.

- `src/Fields.jl`:1233  (_context_grid)
- `src/Fields.jl`:1245  (_context_layout)
- `src/Fields.jl`:1716  (_kernel_data)
- `src/Fields.jl`:2913  (_shared_mode_axis)
- `src/Fields.jl`:2948  (_shared_mode_pair)
- `src/Fields.jl`:3079  (_shared_modes!)
- `src/Fields.jl`:2973  (_write_shared_mode!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `874ed65b`)

### 2026-09-24-documentation-review-01-049  Some check and pass helpers never state what they return, while their siblings on the same page say 'Returns `nothing` or throws.'

Rule: `RULE.DOC.RETURNS`.  
Reported by `withheld@api-Fields`, decided by an agent.

`_check_adapt_target`, `_check_broadcast_field_compatibility` and `_check_family_element_type` state neither an arrow nor a Returns sentence; `_reality_projection_planes!` and `_shared_modes_pass!` are mutators with no stated result.

**Fix.** Add 'Returns `nothing` or throws.' to the checks and a return sentence to the two pass helpers, as the sibling checks already do.

- `src/Fields.jl`:2542  (_check_adapt_target)
- `src/Fields.jl`:2094  (_check_broadcast_field_compatibility)
- `src/Fields.jl`:908  (_check_family_element_type)
- `src/Fields.jl`:2783  (_reality_projection_planes!)
- `src/Fields.jl`:3003  (_shared_modes_pass!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `ca2fa0b5`)

### 2026-09-24-documentation-review-01-050  Package terms for operation classes are used as if already known: the page names families of operations it never describes, so a cold reader cannot tell which operations the R <= 2 ceiling applies to.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-GBGPeriodicFields`, decided by an agent.

Nothing on the page says what a fiber-preserving or a mapped reduction is, which operations make up the decomposition family, or what the local-spline transfer is. The only later mention is the Interpolation bullet, which speaks of the grid-to-point transfer and a choice of scheme, not of splines.

**Fix.** Gloss each term in a clause, for example: 'reductions that return a fiber-valued mean, and reductions taking a leading fiber map such as mean(det, A)'; 'the symmetric/skew/deviatoric decomposition'; 'the local-spline interpolation between grid and points'. Otherwise drop the names and link the owning module.

- `src/GBGPeriodicFields.jl`:59  (GBGPeriodicFields)
- `src/GBGPeriodicFields.jl`:58  (GBGPeriodicFields)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `84b09c7f`)

### 2026-09-24-documentation-review-01-051  The storage-family paragraph lists a field's 'multipliers' and 'kernels' as objects adapt moves before the page has said what either is. Multipliers are mentioned only later, and only as the way operators are applied. Kernels are said only to be 'not a field'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-GBGPeriodicFields`, decided by an agent.

'its multipliers' implies a per-field object that a cold reader has no way to picture. The Convolution bullet says only 'A kernel is its own kind of object rather than a field', which states what a kernel is not.

**Fix.** Bind them where they are first used, for example: 'the wavenumber multipliers its differential operators are applied with, the convolution kernels built from them'.

- `src/GBGPeriodicFields.jl`:47  (GBGPeriodicFields)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `951f3f99`)

### 2026-09-24-documentation-review-01-052  The resolved-band definition leans on 'the package's two wavenumber families' and names them the 'derivative family' and the 'squared family' without saying what they are.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-GBGPeriodicFields`, decided by an agent.

A reader not already inside the package has to infer that one family is the wavenumber k used for first derivatives and the other is |k|^2 used for the Laplacian. The sentence refers to them as known objects.

**Fix.** Say it outright: 'the wavenumbers used for first derivatives are zeroed at the Nyquist frequency, while the squared wavenumbers used for the Laplacian keep the true value there'.

- `src/GBGPeriodicFields.jl`:29  (GBGPeriodicFields)
- pass 1: blind verifier `NOT_FIXED`  (commit `172ccafe`)
- pass 2: blind verifier `FIXED`, with the diff `FIXED`  (commit `172ccafe`)

### 2026-09-24-documentation-review-01-053  The symbol R is used as the tensor order without ever being named as such. The page shows it only beside a list of tensor kinds and then treats it as a type parameter.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-GBGPeriodicFields`, decided by an agent.

No clause says 'R, the tensor order (the number of fiber indices)'. The reader has to infer the binding from the dash, and the next paragraph relies on it with 'The field and point-value types are parameterized on `R`' and 'General `R`'.

**Fix.** Write 'Sections of tensor order $R = 0, 1, 2$ (scalar, vector, second-order tensor)', or add a clause binding R.

- `src/GBGPeriodicFields.jl`:52  (GBGPeriodicFields)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `10b6c74b`)

### 2026-09-24-documentation-review-01-054  The page uses the package's internal development vocabulary ('a test lane', 'the umbrella', 'public surface') where a first-time reader has no referent for it.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-GBGPeriodicFields`, decided by an agent.

'Test lane' is testing-harness jargon, and the page never defines it. 'The umbrella' means the top-level module, but nothing on the page calls it that before this sentence.

**Fix.** Write 'the test suite checks that', and 'The top-level module assembles its public interface from the submodules below'.

- `src/GBGPeriodicFields.jl`:63  (GBGPeriodicFields)
- `src/GBGPeriodicFields.jl`:72  (GBGPeriodicFields)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `0a453955`)

### 2026-09-24-documentation-review-01-055  A backtick span holds REPL help-mode input, which is not a well-formed Julia expression.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@api-GBGPeriodicFields`, decided by an agent.

`?Fields` is a keystroke at the REPL prompt that switches to help mode. As Julia source it does not parse, and the rule admits only names, types, calls and expressions in a code span.

**Fix.** Write 'typing `?` followed by the module name at the REPL, as for `Fields` or `Convolution`', or cite the modules as `Fields` and `Convolution` directly.

- `src/GBGPeriodicFields.jl`:72  (GBGPeriodicFields)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`

### 2026-09-24-documentation-review-01-058  'The usual ceiling' on tensor order is used as though the reader already knows it. The page never states what the ceiling is.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Interpolation`, decided by an agent.

The `out` bullet of `interpolate!` says the transfer serves tensor orders above the usual ceiling. The page never states that ceiling (orders below 3).

**Fix.** State the ceiling: most operations support tensor orders up to 2, and the local-spline transfer also serves order 3 and above.

- `src/Interpolation.jl`:1115  (interpolate!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `a33a6f94`)

### 2026-09-24-documentation-review-01-059  Internal docstrings cite 'invariant 14' and 'decision 40', which are design-document numbers that mean nothing on this page.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Interpolation`, decided by an agent.

A reader on this page cannot tell what invariant 14 refuses or what 'the fixed tree of decision 40' is.

**Fix.** State the content instead of the number: sections of different precision are refused against each other, and a threaded float reduction needs a fixed reduction tree to be thread-count invariant.

- `src/Interpolation.jl`:2085  (_show_spline_eltype)
- `src/Interpolation.jl`:686  (_scan_offsets!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `97c651d4`)

### 2026-09-24-documentation-review-01-060  'The folded rfft axis' is a package term that the page uses without defining it.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Interpolation`, decided by an agent.

The `DirectDFT` docstring defines the Parseval weight through 'the zero plane of the folded rfft axis', and nothing on the page says which axis is folded or what folding means.

**Fix.** Gloss it: the axis the real-to-complex transform halves, on which only the non-negative frequencies are stored.

- `src/Interpolation.jl`:1347  (DirectDFT)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `dad56861`)

### 2026-09-24-documentation-review-01-063  Several prose sentences have no verb and read as note-style fragments.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Interpolation`, decided by an agent.

'Same verbs, one adjointness contract, the one non-uniformity documented below' has no verb. The same is true of 'Horner over …', 'Pure scalar arithmetic, kernel-safe.' and 'A host-side helper for spline weights.'

**Fix.** Restore the verbs, for example 'All schemes share the same verbs and one adjointness contract'; 'It evaluates the columns by Horner's rule'; 'It is pure scalar arithmetic, safe inside a kernel'; 'It is a host-side helper'.

- `src/Interpolation.jl`:121  (Interpolation)
- `src/Interpolation.jl`:400  (_axis_weights)
- `src/Interpolation.jl`:418  (_locate)
- `src/Interpolation.jl`:285  (_fornberg)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `0bbd287d`)

### 2026-09-24-documentation-review-01-064  Several identity sentences are bare noun phrases with no verb.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Interpolation`, decided by an agent.

The `AbstractTransferScheme`, `AbstractSplineScheme`, `LagrangeSpline` and the host `_scan_offsets!` docstrings each open with a verbless noun phrase, some of them followed by a colon.

**Fix.** Give each a subject and verb: 'An `AbstractTransferScheme` is the supertype of…'; '`LagrangeSpline` interpolates locally with the unique…'; 'This method computes the threaded inclusive running total…'.

- `src/Interpolation.jl`:114  (Interpolation)
- `src/Interpolation.jl`:145  (Interpolation)
- `src/Interpolation.jl`:235  (LagrangeSpline)
- `src/Interpolation.jl`:681  (_scan_offsets!)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `9297f2f8`)

### 2026-09-24-documentation-review-01-065  The page cites numbered design rules ('invariant 10', 'invariant 14', 'decision 73') that are defined nowhere on the page and are not linked, so a cold reader cannot follow them; the public displace! docstring is one of the sites.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Points`, decided by an agent.

Nothing on the page states what invariant 10, invariant 14 or decision 73 says; 'α/β' is also never glossed here.

**Fix.** Replace each number with the statement it stands for (for instance, 'the α/β accumulation scalars the in-place operations take'), or drop the citation.

- `src/Points.jl`:1345  (displace!)
- `docs/src/api/Points.md`:73  (Points / Internal API)
- `src/Points.jl`:1257  (_check_displacement_compatibility)
- `src/Points.jl`:1289  (_check_displacement_domain)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `8304319b`)

### 2026-09-24-documentation-review-01-067  Several package-internal nouns are used without explanation: 'fused values functions', 'formula builders', 'storage family', 'backend', 'the arbitrary-fiber-map escape hatch', the 'no-consumer reason' and 'speculative structure'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Points`, decided by an agent.

None of these terms is defined on the page. 'Storage family' is used first in a section heading ('Moving between storage families') and is never explained.

**Fix.** Gloss 'storage family' at first use (host Array, CuArray or ROCArray). Cut the codegen implementation nouns from the module map, and restate the combine! reason in plain words: nothing needs it on points, so it has not been built.

- `src/Points.jl`:22  (Points)
- `src/Points.jl`:1351  (displace!)
- `docs/src/api/Points.md`:45  (Points / Point-value algebra)
- `docs/src/api/Points.md`:49  (Points / Point-value algebra)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `96c17e16`)

### 2026-09-24-documentation-review-01-069  The module map has a verbless fragment.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Points`, decided by an agent.

'The one family that couples base and fiber' has no verb.

**Fix.** Rewrite as: 'It is the one family that couples base and fiber, and positions deliberately have no `+` with point values.'

- `src/Points.jl`:28  (Points)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `3e63d00a`)

### 2026-09-24-documentation-review-01-070  The displace! docstring never says what the mutator returns. Its signatures carry no arrow and no 'Returns' sentence appears, while its sibling wrap! does state 'returns `points`'. Several internal check helpers also omit their return value; _check_npoints_match states one.

Rule: `RULE.DOC.RETURNS`.  
Reported by `withheld@api-Points`, decided by an agent.

The identity sentence does not name the result, and the result is stated nowhere in the docstring.

**Fix.** Add a sentence such as 'The call runs in place and returns `destination`.' before the caveats, and state the return value (for example `nothing`) on the check helpers.

- `src/Points.jl`:1306  (displace!)
- `src/Points.jl`:1256  (_check_displacement_compatibility)
- `src/Points.jl`:480  (_check_combinable)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `21c2d166`)

### 2026-09-24-documentation-review-01-071  Two backtick spans do not hold well-formed Julia. `1 point` and `500 points` are printed output text, not expressions, and a bare `{R}` does not parse on its own.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@api-Points`, decided by an agent.

In Julia, `1 point` with a space is a syntax error, and `{R}` alone is discontinued brace syntax.

**Fix.** Quote the printed output as strings (`"1 point"`, `"500 points"`), and write the parameter as `TensorPointValues{R}`.

- `src/Points.jl`:1485  (_show_count)
- `src/Points.jl`:217  (TensorPointValues)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `c071af88`)

### 2026-09-24-documentation-review-01-072  Several sentences on the page have no verb or no subject: they read as tags, not sentences.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Reductions`, decided by an agent.

The module's first sentence is a noun phrase with a dash and no verb. 'The parts are, each linking...' breaks off after 'are'. The others are fragments with no subject, or no finite verb.

**Fix.** Give each one a subject and a verb, e.g. 'This module holds the L² / measure structure...', 'It is defined in spectral representation only...', 'It is physical-space only...', 'It is computed in one fused mapped pass...', 'The parts are listed below; each links to...'.

- `src/Reductions.jl`:4  (Reductions)
- `src/Reductions.jl`:19  (Reductions)
- `src/Reductions.jl`:1002  (weighted_inner)
- `src/Reductions.jl`:684  (cov)
- `src/Reductions.jl`:608  (Reductions)
- `src/Reductions.jl`:990  (weighted_inner)
- `src/Reductions.jl`:684  (cov)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `3dbf0671`)

### 2026-09-24-documentation-review-01-076  The page uses 'the folded axis' and the rfft half-spectrum weighting before it says what they are, and it never explains the folding.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Reductions`, decided by an agent.

The inner warning uses 'the folded axis' first. The weighted_inner docstring, further down, only identifies it as `fft_dims[1]` of an unexplained 'layout'. Nothing on the page says that a real-to-complex transform stores half the spectrum along one axis.

**Fix.** At first use, add a clause: 'the real-to-complex transform stores only half the modes along one axis (the folded axis, `fft_dims[1]` of the field's layout), so every other mode stands for a conjugate pair and counts twice'.

- `src/Reductions.jl`:753  (inner)
- `src/Reductions.jl`:772  (inner)
- `src/Reductions.jl`:1004  (weighted_inner)
- pass 1: blind verifier `FIXED`, with the diff `LINE_ONLY`  (commit `304c430e`)
- pass 2: blind verifier `FIXED`, with the diff `FIXED`  (commit `304c430e`)

### 2026-09-24-documentation-review-01-078  The radial reductions use symbols they never bind: N, the per-axis N_a, L_a, Δx_a and the axis index a.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Reductions`, decided by an agent.

In `radial_spectrum` and `radial_correlation`, N appears in the normalisation and neither docstring says it is the number of grid points. N_a, L_a and Δx_a are never said to be the points, side length and spacing along axis a, and a is never said to index the axes. Other docstrings bind N, but each docstring must read on its own.

**Fix.** Add one binding clause to each: 'where N is the number of grid points, and N_a, L_a and Δx_a = L_a/N_a are the point count, side length and spacing along axis a'.

- `src/Reductions.jl`:1327  (radial_spectrum)
- `src/Reductions.jl`:1365  (radial_spectrum)
- `src/Reductions.jl`:1499  (radial_correlation)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `dab87289`)

### 2026-09-24-documentation-review-01-079  Some prose points to the package's development history, which the reader cannot see.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Reductions`, decided by an agent.

A dated fix, 'gained', 'used to produce' and 'having been fused' describe changes to the code over time. A first-time reader does not know the earlier state, and the page gives no way to look it up.

**Fix.** State the current behaviour only, for example 'both reduce on the same threaded fixed tree, so they agree as threads are added'; 'std/var also have a scalar Parseval form'.

- `src/Reductions.jl`:1022  (weighted_inner)
- `src/Reductions.jl`:755  (inner)
- `src/Reductions.jl`:316  (_tree_dims_reduce)
- `src/Reductions.jl`:1519  (radial_correlation)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `2176db97`)

### 2026-09-24-documentation-review-01-080  A backtick span holds a mathematical equality, not Julia code.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@api-Reductions`, decided by an agent.

The text means the identity g = f between the two arguments, which the same docstring writes in LaTeX as 'the $g = f$ case'. As code, `g = f` is an assignment.

**Fix.** Write it as $g = f$, matching the sibling sentence.

- `src/Reductions.jl`:974  (weighted_inner)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `bd0d9d8e`)

### 2026-09-24-documentation-review-01-081  Several list entries are verbless label-dash fragments (a name, a dash or colon, then a noun phrase), not sentences.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@architecture`, decided by an agent.

The map entries, the validity table rows, the scheme-family entries and the point data-type entries each carry no finite verb.

**Fix.** Give each entry a subject and verb, e.g. 'The `Convolution` module applies the kernel multiply ...'.

- `docs/ARCHITECTURE.md`:196  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / The architecture map)
- `docs/ARCHITECTURE.md`:197  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / The architecture map)
- `docs/ARCHITECTURE.md`:289  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / Representation validity lives in the method set)
- `docs/ARCHITECTURE.md`:891  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:971  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:314  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / Representation validity lives in the method set)
- `docs/ARCHITECTURE.md`:316  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / Representation validity lives in the method set)
- `docs/ARCHITECTURE.md`:1086  (Architecture — GBGPeriodicFields / 11. Convolution)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `6d2a5535`)

### 2026-09-24-documentation-review-01-082  The term 'values function' is used as a term of art and never defined on the page.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@architecture`, decided by an agent.

It appears twice in §9 as if the reader knew what the fused executor stamps; no clause says what a values function is.

**Fix.** Define it at first use: the per-element function that reads an element's source values and returns its output values.

- `docs/ARCHITECTURE.md`:676  (Architecture — GBGPeriodicFields / 9. Performance model and CPU threading)
- `docs/ARCHITECTURE.md`:708  (Architecture — GBGPeriodicFields / 9. Performance model and CPU threading)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `4ce268a2`)

### 2026-09-24-documentation-review-01-083  Package-internal testing and performance jargon is used with no definition on the page: the pass-audit row, its fused ideal and named holder, the finding-(k) hoist, decision 47's dispatch-target guard.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@architecture`, decided by an agent.

None of these nouns is explained in a clause; each assumes the test suite or PERFORMANCE.md is in hand.

**Fix.** Gloss each in a clause (e.g. 'the pass audit, which counts each array's element reads and writes against the fused minimum') or drop it from this page.

- `docs/ARCHITECTURE.md`:731  (Architecture — GBGPeriodicFields / 9. Performance model and CPU threading)
- `docs/ARCHITECTURE.md`:719  (Architecture — GBGPeriodicFields / 9. Performance model and CPU threading)
- `docs/ARCHITECTURE.md`:758  (Architecture — GBGPeriodicFields / 9. Performance model and CPU threading)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `e5cad893`)

### 2026-09-24-documentation-review-01-084  'Compressed kernels' is used in §9 before the page says what a compressed kernel is, and §11 later uses it again without defining it.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@architecture`, decided by an agent.

§11 lists the four storage classes but never states that 'compressed' means the non-stored ones.

**Fix.** Say at first use that a compressed kernel is one not held as one coefficient per mode (separable, radial, product).

- `docs/ARCHITECTURE.md`:715  (Architecture — GBGPeriodicFields / 9. Performance model and CPU threading)
- `docs/ARCHITECTURE.md`:1081  (Architecture — GBGPeriodicFields / 11. Convolution)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `500297f0`)

### 2026-09-24-documentation-review-01-085  The 'umbrella module' (and its 'AI-tips block') is referred to but never defined on the page.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@architecture`, decided by an agent.

A cold reader does not know the umbrella is the top-level `GBGPeriodicFields` module that re-exports the submodules.

**Fix.** Name it: 'the umbrella module `GBGPeriodicFields`, which includes and re-exports the submodules'.

- `docs/ARCHITECTURE.md`:9  (Architecture — GBGPeriodicFields)
- `docs/ARCHITECTURE.md`:362  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / Naming conventions)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `bdd68475`)

### 2026-09-24-documentation-review-01-086  Two package phrases carry a meaning the page never gives: 'the resolved band', and 'the divergence-free reference' said of `DirectDFT`.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@architecture`, decided by an agent.

The resolved band is used as the scope of exactness claims without saying which modes it contains (sub-Nyquist); 'divergence-free reference' reads as a statement about the divergence operator and is not explained.

**Fix.** Define the resolved band at first use (the stored modes below the Nyquist frequency) and say what 'divergence-free reference' means (it preserves a solenoidal field's zero divergence exactly).

- `docs/ARCHITECTURE.md`:121  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / The fiber-bundle model)
- `docs/ARCHITECTURE.md`:902  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `9e0ef574`)

### 2026-09-24-documentation-review-01-088  The page points at things it does not contain: an 'item 17' that exists nowhere on the page, and a header promising that each decision-log entry reads on its own in this file, when the log now lives in another document.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@architecture`, decided by an agent.

No item 17 is on the page; the last section says the decision log is `docs/DECISIONS.md`, so the header's self-containment claim about decision-log entries describes a different file.

**Fix.** Replace 'item 17' with the decision it means, linked; reword the header to say the decision log is a separate document.

- `docs/ARCHITECTURE.md`:939  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:14  (Architecture — GBGPeriodicFields)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `2e0507c7`)

### 2026-09-24-documentation-review-01-089  Several backtick spans hold shorthand that is not well-formed Julia: an optional-index notation, slash-joined type-name pairs, a range written with `..` over a name suffix, ellipsis placeholders, and TurTLE's name template.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@architecture`, decided by an agent.

`i(, j)` does not parse; `ScalarFieldPhysical/Spectral` and `FiberTensor3/4` parse as divisions naming nonexistent bindings; `wavenumber_1..3`, `_check_…`, `SubArray{…,<:Array}` and `beta_n{n}_m{m}` are not Julia expressions.

**Fix.** Write the names out in full (`ScalarFieldPhysical`/`ScalarFieldSpectral`, `FiberTensor3`/`FiberTensor4`, `wavenumber_1`, …, `wavenumber_3`), and move the placeholder shapes into prose or LaTeX.

- `docs/ARCHITECTURE.md`:416  (Architecture — GBGPeriodicFields / 3. Types and memory layout)
- `docs/ARCHITECTURE.md`:404  (Architecture — GBGPeriodicFields / 3. Types and memory layout)
- `docs/ARCHITECTURE.md`:453  (Architecture — GBGPeriodicFields / 4. Spectral machinery)
- `docs/ARCHITECTURE.md`:659  (Architecture — GBGPeriodicFields / 9. Performance model and CPU threading)
- `docs/ARCHITECTURE.md`:953  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:989  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `ee513c11`)

### 2026-09-24-documentation-review-01-092  Package vocabulary about tensor structure is used undefined: 'fiber', 'rank-R field' and 'tensor order' are never explained on the page, yet the plan-reuse argument and the L_11 relation rest on them.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@examples-hist_cpu`, decided by an agent.

**Fix.** Say in a clause that the fiber is the value at one grid point (a scalar, a 3-vector, a 3x3 tensor) and the tensor order R counts its indices, or link the package's glossary.

- `examples/HIST_CPU.jl`:336  (run_hist)
- `examples/HIST_CPU.jl`:430  (run_hist)
- pass 1: blind verifier `NOT_FIXED`  (commit `b20d4c67`)
- pass 2: blind verifier `FIXED`, with the diff `FIXED`  (commit `b20d4c67`)

### 2026-09-24-documentation-review-01-094  The tensor order R is a mathematical symbol set as a code span inside a prose word; it names no code object on the page and should be LaTeX.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@examples-hist_cpu`, decided by an agent.

**Fix.** Write rank-$R$ (inline LaTeX) instead of rank-`R`.

- `examples/HIST_CPU.jl`:336  (run_hist)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`

### 2026-09-24-documentation-review-01-095  Command-line flags are set in backtick spans although they are not well-formed Julia (a leading '--' does not parse); the rule admits only Julia in a code span. Possibly accepted practice for CLI flags, hence flagged as uncertain.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@examples-hist_cpu`, decided by an agent.

**Fix.** Either accept CLI flags as a recorded exception to the rule, or name the configuration by its Julia constructor (`smoke()`, `huge()`) in prose and keep flags only inside the shell code block.

!!! warning "The code may be what is wrong"
    The reader believed the documentation and the code disagree, and that the code is the wrong half. That is a question for the owner, not a documentation fix.

- `examples/HIST_CPU.jl`:86
- `examples/HIST_CPU.jl`:115
- `examples/gpu/rocm/HIST_ROCm.jl`:80

### 2026-09-24-documentation-review-01-097  The check for unified memory calls `field_data`, a package accessor that nothing on the page introduces. A reader cannot tell that it returns the field's underlying device array, which is the whole point of the check.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@gpu`, decided by an agent.

The name appears once, inside the verification sentence, and has no gloss.

**Fix.** Say what it returns: 'CUDA.is_unified(field_data(u)), where field_data returns the array holding u's values, which returns true'.

- `docs/src/gpu.md`:111  (Running on a GPU / CUDA (NVIDIA) / Fields larger than GPU memory)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `435c067e`)

### 2026-09-24-documentation-review-01-098  The symbols N and M in the Interpolation entry are bound nowhere on the page, so a cold reader cannot tell what the rescaling factor N/M is; W and its transpose are bound as gather and scatter, but N and M are not.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@home`, decided by an agent.

The page never says what N and M count. The only nearby link goes to another page (Formalization), and a link to another page does not bind a symbol on this one.

**Fix.** Bind them in the sentence, e.g. 'once rescaled by $N/M$, the ratio of grid points $N$ to points $M$'.

- `docs/src/index.md`:50  (GBGPeriodicFields.jl / Main components)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `57b09891`)

### 2026-09-24-documentation-review-01-099  The Fields entry uses the package's own nouns 'multipliers', 'plans' and 'the reality condition' as if the reader already knows them. None is defined or linked on the page, and nothing earlier says a field HAS multipliers or plans.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@home`, decided by an agent.

The vocabulary paragraph defines section, fiber and base only. 'its multipliers, kernels or plans' treats multipliers and plans as a field's belongings, and 'the reality condition' is used with a definite article and no gloss.

**Fix.** Gloss each in a clause (the wavenumber multipliers that apply the differential operators; the precomputed FFT plans; the condition that the coefficients are the spectrum of a real field), or link each to its docstring.

- `docs/src/index.md`:45  (GBGPeriodicFields.jl / Main components)
- `docs/src/index.md`:45  (GBGPeriodicFields.jl / Main components)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `b84d3852`)

### 2026-09-24-documentation-review-01-100  The Convolution entry says a kernel comes in 'four interchangeable storage classes' but never names them or says how they differ, so the phrase tells a cold reader nothing.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@home`, decided by an agent.

No class is named on the page, and no link is given for them.

**Fix.** Name the four (stored, separable, radial, product) in a clause, or link the kernel-storage-class section of the Convolution API page.

- `docs/src/index.md`:48  (GBGPeriodicFields.jl / Main components)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `e1f283dd`)

### 2026-09-24-documentation-review-01-101  Package jargon with no gloss: 'the pairing' in the Reductions entry (what pairing? nothing on the page introduced one), 'the fused symmetric gradient' (what 'fused' means here), and 'the field surface' in the Points entry (the set of operations).

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@home`, decided by an agent.

'resolve the pairing over wavenumber or separation shells' uses a definite article for a pairing the page never introduces; 'fused' and 'surface' are in-house words for a single-pass kernel and the public method set.

**Fix.** Write 'resolve the inner product over wavenumber or separation shells'; 'the symmetric gradient, computed in one pass without the full gradient'; 'mirroring the field operations'.

- `docs/src/index.md`:51  (GBGPeriodicFields.jl / Main components)
- `docs/src/index.md`:47  (GBGPeriodicFields.jl / Main components)
- `docs/src/index.md`:49  (GBGPeriodicFields.jl / Main components)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `076f7fc9`)

### 2026-09-24-documentation-review-01-103  The page uses 'anterpolation' in the $q$ row before defining it. It is defined only later, in the Operators table's $W$ row, as the adjoint scatter.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@notation`, decided by an agent.

The first definition appears in the later row: 'interpolation (gather) and its adjoint anterpolation (scatter)'.

**Fix.** Gloss it where it first appears, e.g. 'that anterpolation (the adjoint of interpolation, scattering point values onto the grid) deposits'.

- `docs/src/notation.md`:28  (Notation / Base and fiber)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `d3e7116d`)

### 2026-09-24-documentation-review-01-104  The page uses the base measure $\mu$ (and 'the same measure', 'the normalized $L^2$ inner product') without binding it. Nothing says that the measure is the cell volume on a grid and counting on a point set, or what 'normalized' divides by.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@notation`, decided by an agent.

No row defines $\mu$ or 'base measure'. The $\langle\cdot,\cdot\rangle$ row says only 'normalized' without saying what it is normalized by.

**Fix.** Add a $\mu$ row stating that the base measure is the cell volume on a Grid3D and the counting measure on a PointSet, and that the normalized inner product and the mean divide by the total measure.

- `docs/src/notation.md`:16  (Notation / Conventions)
- `docs/src/notation.md`:57  (Notation / Operators)
- `docs/src/notation.md`:60  (Notation / Operators)
- `docs/ARCHITECTURE.md`:159  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / The fiber-bundle model)
- `docs/ARCHITECTURE.md`:393  (Architecture — GBGPeriodicFields / 2. The central principle: the architecture follows established mathematics / Documentation policy)
- `docs/ARCHITECTURE.md`:834  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:1114  (Architecture — GBGPeriodicFields / 12. Reductions)
- `examples/HIST_CPU.jl`:428  (run_hist)
- `examples/HIST_CPU.jl`:433  (run_hist)
- `examples/HIST_CPU.jl`:526
- `examples/HIST_CPU.jl`:528
- `examples/gpu/rocm/HIST_ROCm.jl`:432  (run_hist)
- `examples/gpu/rocm/HIST_ROCm.jl`:435  (run_hist)
- `src/Convolution.jl`:966  (convolve!)
- `src/DifferentialOperators.jl`:1400  (inverse_laplacian!)
- `src/DifferentialOperators.jl`:1401  (inverse_laplacian!)
- `src/DifferentialOperators.jl`:1407  (inverse_laplacian!)
- `src/DifferentialOperators.jl`:1408  (inverse_laplacian!)
- `src/Reductions.jl`:469  (integral)
- `src/Reductions.jl`:476  (integral)
- `src/Reductions.jl`:488  (integral)
- `src/Reductions.jl`:497  (integral)
- `src/Reductions.jl`:765  (inner)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `cf93ee08`)

### 2026-09-24-documentation-review-01-105  The $N$ row writes the per-axis counts $N_i$ in $\prod_i N_i$ and never binds them. The same row then has $N$ 'count per axis' in the storage claims, which is a second meaning of $N$ with no symbol of its own.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@notation`, decided by an agent.

$N_i$ appears only in this formula. The following sentence reads $O(N^3)$ and $O(N)$ with $N$ as a per-axis count, and no glyph marks that reading.

**Fix.** Bind $N_i$ as the number of grid points along axis $i$, and name the per-axis reading explicitly, e.g. 'with $N_i = N^{1/3}$ on a cubic grid'.

- `docs/src/notation.md`:31  (Notation / Base and fiber)
- pass 1: blind verifier `FIXED`, with the diff `LINE_ONLY`  (commit `0cc43d1a`)
- pass 2: blind verifier `FIXED`, with the diff `FIXED`  (commit `0cc43d1a`)

### 2026-09-24-documentation-review-01-106  Several package or specialist nouns are used without a gloss. The $\hat f$ row says 'in spectral representation' but never says that this means the field's Fourier coefficients as the forward transform stores them. 'CIC' is not expanded. 'the kernel and reduction families' names package groupings the page never introduces.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@notation`, decided by an agent.

None of the three terms has a clause or a link on this page.

**Fix.** Gloss 'spectral representation' as the rfft coefficients of the same field, expand CIC as cloud-in-cell, and name the operations the 'kernel and reduction families' mean, or drop the word 'families'.

- `docs/src/notation.md`:38  (Notation / Base and fiber)
- `docs/src/notation.md`:62  (Notation / Operators)
- `docs/src/notation.md`:31  (Notation / Base and fiber)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `dfa4b5b7`)

### 2026-09-24-documentation-review-01-108  Several Convention-column cells are verbless fragments set as sentences, and they sit beside cells written as full sentences in the same column.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@notation`, decided by an agent.

Each has a capital letter and a full stop but no subject or verb. The neighbouring cells ('An index repeated within a term is summed...', 'Every macro argument is braced...') are full sentences.

**Fix.** Give each a verb, e.g. 'The three sums run over the $N$ grid points, the $M$ points, and the Fourier modes.' and 'It is always set upright — never ...'.

- `docs/src/notation.md`:17  (Notation / Conventions)
- `docs/src/notation.md`:12  (Notation / Conventions)
- `docs/src/notation.md`:13  (Notation / Conventions)
- `docs/ARCHITECTURE.md`:475  (Architecture — GBGPeriodicFields / 4. Spectral machinery)
- `docs/ARCHITECTURE.md`:490  (Architecture — GBGPeriodicFields / 4. Spectral machinery)
- `docs/ARCHITECTURE.md`:491  (Architecture — GBGPeriodicFields / 4. Spectral machinery)
- `docs/ARCHITECTURE.md`:894  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:895  (Architecture — GBGPeriodicFields / 10. Interpolation and anterpolation (the grid↔point transfer layer))
- `docs/ARCHITECTURE.md`:1096  (Architecture — GBGPeriodicFields / 11. Convolution)
- `src/Convolution.jl`:1908  (translation_kernel)
- `src/Convolution.jl`:1913  (translation_kernel)
- `src/DifferentialOperators.jl`:114  (_apply_spectral_divergence!)
- `src/DifferentialOperators.jl`:118  (_apply_spectral_divergence!)
- `src/DifferentialOperators.jl`:381  (_scalar_gradient_modes!)
- `src/DifferentialOperators.jl`:453  (_vector_gradient_modes!)
- `src/DifferentialOperators.jl`:536  (_curl_modes!)
- `src/DifferentialOperators.jl`:579  (DifferentialOperators)
- `src/DifferentialOperators.jl`:712  (_symmetric_gradient_modes!)
- `src/DifferentialOperators.jl`:800  (gradient!)
- `src/DifferentialOperators.jl`:807  (gradient!)
- `src/DifferentialOperators.jl`:808  (gradient!)
- `src/DifferentialOperators.jl`:901  (divergence!)
- `src/DifferentialOperators.jl`:908  (divergence!)
- `src/DifferentialOperators.jl`:909  (divergence!)
- `src/DifferentialOperators.jl`:1108  (curl!)
- `src/DifferentialOperators.jl`:1109  (curl!)
- `src/DifferentialOperators.jl`:1115  (curl!)
- `src/DifferentialOperators.jl`:1116  (curl!)
- `src/DifferentialOperators.jl`:1117  (curl!)
- `src/DifferentialOperators.jl`:1191  (inverse_curl!)
- `src/DifferentialOperators.jl`:1267  (symmetric_gradient!)
- `src/DifferentialOperators.jl`:1272  (symmetric_gradient!)
- `src/Fields.jl`:1757  (FieldSpectralMultipliers)
- `src/Interpolation.jl`:1340  (DirectDFT)
- `src/Interpolation.jl`:1341  (DirectDFT)
- `src/Interpolation.jl`:1342  (DirectDFT)
- `src/Interpolation.jl`:1366  (DirectDFT)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `c9db6f6c`)

### 2026-09-24-documentation-review-01-109  Mathematics in rendered prose written as a backticked code span or plain ASCII rather than LaTeX: the tensor-order symbol R is backticked though it names nothing in the code, and the 2/3 rule and a convolution identity appear as plain text while the same page writes ``2/3`` as math elsewhere.

Rule: `RULE.DOC.LITERATE`.  
Reported by `withheld@source-examples-HIST_CPU-jl-322198`, decided by an agent.

**Fix.** Write rank ``R`` and the ``2/3`` rule as LaTeX, and state the convolution relation in words or as a formula.

- `examples/HIST_CPU.jl`:336  (run_hist)
- `examples/HIST_CPU.jl`:342  (run_hist)
- `examples/HIST_CPU.jl`:125
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `afd83372`)

### 2026-09-24-documentation-review-01-110  Rendered prose uses package terms of art a cold reader of this page is never given: 'fiber', 'tensor order' and 'contracts the fiber' are nowhere defined on the page.

Rule: `RULE.DOC.LITERATE`.  
Reported by `withheld@source-examples-HIST_CPU-jl-322198`, decided by an agent.

**Fix.** Say in a clause what the fiber is (the value at one point: a scalar, a 3-vector, a 3x3 tensor) and what contracting it means here (the dot product u(x)·u(x+r)).

- `examples/HIST_CPU.jl`:337  (run_hist)
- `examples/HIST_CPU.jl`:430  (run_hist)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `f67c7a70`)

### 2026-09-24-documentation-review-01-113  A rendered sentence opens with a lowercase word, and the Method paragraph's opening is a participle fragment with no main verb.

Rule: `RULE.DOC.LITERATE`.  
Reported by `withheld@source-examples-HIST_CPU-jl-322198`, decided by an agent.

**Fix.** Capitalize and give a verb ('The divergence check ... should be at round-off'); make the Method opener a sentence ('We write ...').

- `examples/HIST_CPU.jl`:419  (run_hist)
- `examples/HIST_CPU.jl`:19
- `examples/gpu/rocm/HIST_ROCm.jl`:424  (run_hist)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `d13a75bf`)

### 2026-09-24-documentation-review-01-114  Full-line `# ` comments sit inside the body of `function run_hist`, where they render as prose and split the function's code fence, stranding its header from its body; the file's own `##` convention (used in `make_workspace`, `step!` and the `if` in the stats loop) is not applied here. Fifteen such lines across nine comment blocks.

Rule: `RULE.DOC.LITERATE`.  
Reported by `withheld@source-examples-gpu-rocm-HIST_ROCm-jl-44a260`, decided by an agent.

They are indented two spaces inside `run_hist(p::Params) ... end` (from after `@printf("  device: ...` to before `save_hist`), not at a top-level statement boundary.

**Fix.** Write these as `##` comments, or move the narrative out to top level between definitions.

- `examples/gpu/rocm/HIST_ROCm.jl`:342  (run_hist)
- `examples/gpu/rocm/HIST_ROCm.jl`:348  (run_hist)
- `examples/gpu/rocm/HIST_ROCm.jl`:376  (run_hist)
- `examples/gpu/rocm/HIST_ROCm.jl`:424  (run_hist)
- `examples/gpu/rocm/HIST_ROCm.jl`:449  (run_hist)
- `examples/HIST_CPU.jl`:322  (run_hist)
- `examples/HIST_CPU.jl`:368  (run_hist)
- `docs/ARCHITECTURE.md`:1090  (Architecture — GBGPeriodicFields / 11. Convolution)
- `docs/src/notation.md`:37  (Notation / Base and fiber)
- `examples/HIST_CPU.jl`:34
- `examples/HIST_CPU.jl`:102
- `examples/HIST_CPU.jl`:103
- `examples/HIST_CPU.jl`:124
- `examples/HIST_CPU.jl`:127
- `examples/HIST_CPU.jl`:129
- `examples/HIST_CPU.jl`:235
- `examples/HIST_CPU.jl`:245
- `examples/HIST_CPU.jl`:247
- `examples/HIST_CPU.jl`:272
- `examples/HIST_CPU.jl`:352  (run_hist)
- `examples/HIST_CPU.jl`:372  (run_hist)
- `examples/HIST_CPU.jl`:504
- `examples/HIST_CPU.jl`:505
- `examples/HIST_CPU.jl`:518
- `examples/HIST_CPU.jl`:519
- `examples/gpu/rocm/HIST_ROCm.jl`:91
- `examples/gpu/rocm/HIST_ROCm.jl`:92
- `examples/gpu/rocm/HIST_ROCm.jl`:115
- `examples/gpu/rocm/HIST_ROCm.jl`:117
- `examples/gpu/rocm/HIST_ROCm.jl`:119
- `examples/gpu/rocm/HIST_ROCm.jl`:139
- `examples/gpu/rocm/HIST_ROCm.jl`:142
- `examples/gpu/rocm/HIST_ROCm.jl`:151
- `examples/gpu/rocm/HIST_ROCm.jl`:256
- `examples/gpu/rocm/HIST_ROCm.jl`:266
- `examples/gpu/rocm/HIST_ROCm.jl`:268
- `examples/gpu/rocm/HIST_ROCm.jl`:291
- `examples/gpu/rocm/HIST_ROCm.jl`:362  (run_hist)
- `examples/gpu/rocm/HIST_ROCm.jl`:380  (run_hist)

### 2026-09-24-documentation-review-01-116  The file name `HIST_ROCm.jl` contains an underscore and appears in rendered prose without backticks, although the same paragraph backticks `examples/HIST_CPU.jl`.

Rule: `RULE.DOC.LITERATE`.  
Reported by `withheld@source-examples-gpu-rocm-HIST_ROCm-jl-44a260`, decided by an agent.

It is the opening line of the header prose.

**Fix.** Backtick it: `HIST_ROCm.jl`.

- `examples/gpu/rocm/HIST_ROCm.jl`:2
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `97901ee1`)

### 2026-09-24-documentation-review-01-117  The Differential operators section opens by referring to 'this scalar field', which the reader has not yet met: the scalar field φ is first built in the code block after the paragraph, so the sentence points forward to an object the page has not introduced, and it sits before the section's own introductory sentence.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@tutorial`, decided by an agent.

Up to that sentence the page has built only the vector field u and the spectral buffer; φ = ScalarFieldPhysical(...) appears first in the following code block.

**Fix.** Move the note after the code block (or after the sentence introducing the operators) and name φ explicitly, e.g. 'The plans built above for the vector field u also transform the scalar field φ below.'

- `docs/src/tutorial.md`:66  (Getting started / Differential operators)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `f7370380`)

### 2026-09-24-documentation-review-01-119  The convolution paragraph relies on 'storage class' and a kernel's 'symbol' as if the reader knew the package's kernel taxonomy; neither is defined, and `RadialKernel` is named as one class of an unstated set.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@tutorial`, decided by an agent.

Nothing on the page says what storage classes of kernel exist or that a kernel's symbol is its Fourier multiplier as a function of the wavenumber.

**Fix.** Add a clause: 'a kernel is stored in one of several forms (a coefficient per mode, per-axis factors, or a function of |k| — its symbol — evaluated on the fly)', then say `RadialKernel` is the last of these.

- `docs/src/tutorial.md`:135  (Getting started / Convolution (apply a Fourier kernel))
- pass 1: blind verifier `NOT_FIXED`  (commit `35b427e6`)
- pass 2: blind verifier `FIXED`, with the diff `FIXED`  (commit `35b427e6`)

### 2026-09-24-documentation-review-01-120  Symbols appear in rendered mathematics without a binding on the page: the wavenumber k (in the conjugate-symmetry relation and the cutoff |k| ≤ 4) and f̂ are never said to be the wavenumber vector and the Fourier coefficients; and the energy spectrum paragraph calls inner(u,u) 'the same energy' though the page never called it an energy.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@tutorial`, decided by an agent.

k first appears inside the formula with no clause naming it; 'energy' first appears in the radial-spectrum sentence, while the preceding section described inner(u,u) only as the domain average of |u|^2.

**Fix.** Write 'a real field's Fourier coefficients $\hat f(k)$, indexed by the wavenumber vector $k$, satisfy …', and 'The same quantity ⟨|u|²⟩ (twice the kinetic energy per unit mass), resolved over wavenumber shells …'.

- `docs/src/tutorial.md`:44  (Getting started / Representations: physical ↔ spectral)
- `docs/src/tutorial.md`:138  (Getting started / Convolution (apply a Fourier kernel))
- `docs/src/tutorial.md`:123  (Getting started / Fiberwise algebra and L²/measure reductions)
- pass 1: blind verifier `FIXED`, with the diff `FIXED`  (commit `50c51271`)

## Questions

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-004-code

This finding needs a change only you may make. Will you make it?

Rewrites the display formula of the pullback-pushforward adjunction in ARCHITECTURE §10 (the duality pairing instead of the grid inner product on a measure).

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** not a defect — Owner 2026-09-26: the conversion from measure to density now precedes the identity, which is correct as read.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-006-code

This finding needs a change only you may make. Will you make it?

Moves formulas out of five module docstrings into the operation homes (adjoint identity, (Wf)_p, the covariance, the combination, the rotation rate); every moved formula is a formula edit.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) cd315fbf, 8caadf3c.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-009-code

This finding needs a change only you may make. Will you make it?

Needs Switches in .gbg/config.jl for the settled keyword exceptions (origin, scheme, and corrected if agreed) and possibly making array_type positional, which is code.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) 19826de8.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-010-code

This finding needs a change only you may make. Will you make it?

Rewrites symbols inside formulas (sums over n and i, bar f, tilde k_a, w as a physical kernel, s for f in ARCHITECTURE §2) to the notation page's glyphs.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) f85c346a.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-011-code

This finding needs a change only you may make. Will you make it?

The radial_spectrum formula indexes the shell by round(|k|/Δk) = i where the code's spectrum[i] holds i - 1; the fix changes the formula's index.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) f1e87e8a.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-017-code

This finding needs a change only you may make. Will you make it?

Splits two packed display formulas (cross! components, the l2norm bases) into one row per equation.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) 42d70de2, aca97e2f.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-018-code

This finding needs a change only you may make. Will you make it?

Wraps six display formulas in aligned environments with explicit breaks.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) e7d60b5a, 8e46fbf6.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-016-code

This finding needs a change only you may make. Will you make it?

Three tutorial doctest lines are over-wide (docs/src/tutorial.md:54, 79, 129); a doctest is code to the change guard. The fix binds the spectral shape to a name first; the rest of the finding is committed.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) 8bd71d78.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-114-code

This finding needs a change only you may make. Will you make it?

The only guard-allowed fix (full-line # to ##) turns ~36 lines of run_hist's rendered narrative, with LaTeX, into code comments showing raw LaTeX in both examples. The fix that keeps the narrative rendered restructures run_hist so the prose sits between definitions, which is a code change.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** not a defect — Owner 2026-09-26: the rule targets comments inside control flow; none of these is, and between statements full-line comments are the walkthrough the page is built on.

### 2026-09-24-documentation-review-01-2026-09-24-documentation-review-01-095-code

This finding needs a change only you may make. Will you make it?

Command-line flags such as --smoke are in code spans, which RULE.TEX.CODE_SPAN_JULIA admits only for Julia. Accepting CLI flags is a Switch in .gbg/config.jl; rewriting every mention as the constructor name (smoke(), huge()) is the alternative.

- **fix the code** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **not a defect** — nothing changes, and the finding is closed

**Answered:** fix the code — Done on the owner's ruling, 2026-09-25/26: commit(s) 6205ad31.

