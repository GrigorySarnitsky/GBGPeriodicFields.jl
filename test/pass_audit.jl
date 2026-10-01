# Pass audit — the memory-traffic ledger (ARCHITECTURE decision 36): MEASURE how many times each
# operation actually touches each field-sized array, and pin the counts exactly.
#
# The package's pointwise operations are bandwidth-bound streaming (PERFORMANCE.md §2), so their cost
# IS their element traffic — and none of the other test layers sees it: correctness tests pass an
# unfused op, the allocation audit passes it (recomputation allocates nothing), and only a benchmark
# number drifts, with no ideal beside it to notice. The three-broadcast Helmholtz projection read
# every source component three times per mode from decision 24 until decision 32 rewrote it, and no
# test failed. This audit is the guard that would have caught it on day one.
#
# METHOD. A `CountingArray` wraps a plain `Array` and counts every `getindex`/`setindex!` with atomic
# counters. Fields take generic `AbstractArray` storage (invariant 6), so counting fields flow
# through the whole stack — the field broadcast, `_assign!`, and the KernelAbstractions CPU kernels —
# and each audited call then asserts, for every participating array, its EXACT read and write element
# counts against a frozen table. Beside each frozen count sits the FUSED IDEAL (each needed input
# element read once, each output element written once — the fusion bound of IT's compute audit,
# transplanted from its per-step schedule to the per-operation level, which is the unit a library
# has); a frozen count above its ideal must carry a NAMED HOLDER, and the suite fails an unclaimed
# gap. The audit runs on the CPU only, like the allocation audit and for the same reason: the code is
# generic, so the pass structure is backend-independent, while launch counts and achieved bandwidth
# stay benchmark-side.
#
# UNITS. Counts are absolute element touches (an `Int` per array), computed per case from the shapes —
# not per-array multiples, because legitimate patterns break multiples (`sym!` reads an off-diagonal
# component twice and a diagonal once; the spectral `inner` corrects sub-plane Parseval slabs).
#
# EXCLUSIONS (each has a reason, none is an oversight):
#   * the transform INTERIORS — FFTW's internal passes are FFTW's, not this package's (the same line
#     IT's compute audit draws), and FFT plans reject wrapped storage anyway. An operation
#     *containing* a transform still audits its countable stages: `radial_correlation`'s input read
#     and its physical binning kernel are cases below — the wrapper never reaches the FFT, because
#     `similar` on a CountingArray yields plain storage;
#   * the anterpolation SCATTER — its `Atomix.@atomic` accumulate needs pointer atomics a wrapper
#     array does not provide. The GATHER is audited at its exact per-point stencil counts
#     (M·(2n+2)³ reads per component); extending the atomics onto the wrapper is the
#     recorded route to the scatter;
#   * O(N) configuration arrays (the 1-D wavenumber multipliers, shell vectors, Parseval weight
#     vector) and the per-point POSITIONS — only field- and point-value-shaped storage is wrapped,
#     exactly the scope of IT's pass ledger.
#
# REGENERATION. PASS_AUDIT_PRINT=1 julia --project=. test/pass_audit.jl prints every measured count;
# review each change against the fused ideal — a raised count is a fusion regression unless a new
# holder justifies it — then freeze the new values in the same commit, citing the decision.

using Test
using GBGPeriodicFields
using GBGPeriodicFields: field_data, point_values
using Statistics                              # mean etc. are extended on sections in Reductions
import KernelAbstractions
include("public_surface.jl")

const PRINT_COUNTS = get(ENV, "PASS_AUDIT_PRINT", "0") == "1"


# ---------------------------------------------------------------- the counting harness

# The traffic audit is DECLARED to GBGCodingTools (RULE.TEST.PASS_AUDIT): `CountingArray`, `Traffic`,
# `counting`, `audit` and the completeness check at the foot are the tool's engines,
# `GBGCodingTools.TestHarness`, extracted from this file. A `CountingArray` counts every element read and
# write; each `Traffic` row is one array's frozen `(reads, writes)`, asserted exactly, with the fused
# ideal beside it and a named holder required whenever the two differ; `audit` records the operation
# from the row name's leading token, so completeness is derived rather than remembered.
import GBGCodingTools
using GBGCodingTools.TestHarness: CountingArray, Traffic, counting

# The KA launchers ask the storage for its backend; the tool leaves answering for the wrapper to the
# consumer, since it does not depend on KernelAbstractions.
KernelAbstractions.get_backend(a::CountingArray) = KernelAbstractions.get_backend(a.data)

# `PASS_AUDIT_PRINT=1` still regenerates the table: every measured count is printed beside its frozen one.
audit(operation!, name::String, rows::Traffic...) =
  GBGCodingTools.TestHarness.audit(operation!, name, rows...; print = PRINT_COUNTS)


# ---------------------------------------------------------------- setup

# Mixed axis lengths catch index transpositions; even first axis exercises the Nyquist plane.
const grid = Grid3D((8, 6, 4), (2π, 4π, 6π))
const layout = RealFourierLayout()
const F = GBGPeriodicFields.Fields
const shape0 = F.field_spectral_shape(grid, layout, Val(0))
const shape1 = F.field_spectral_shape(grid, layout, Val(1))
const shape2 = F.field_spectral_shape(grid, layout, Val(2))
const M = prod(shape0[1:3])                   # spectral modes per component
const P = prod(grid.grid_size)                # physical points per component

sspec() = ScalarFieldSpectral(counting(randn(ComplexF64, shape0)), grid)
vspec() = VectorFieldSpectral(counting(randn(ComplexF64, shape1)), grid)
tspec() = TensorFieldSpectral{2}(counting(randn(ComplexF64, shape2)), grid)
sphys() = ScalarFieldPhysical(counting(randn(grid.grid_size...)), grid)
vphys() = VectorFieldPhysical(counting(randn(grid.grid_size..., 3)), grid)
tphys() = TensorFieldPhysical{2}(counting(randn(grid.grid_size..., 3, 3)), grid)

carr(f) = field_data(f)                       # the CountingArray behind a field
# …and behind a kernel: `StoredKernel` wraps the field, so the counted array is one hop further in.
carr(k::GBGPeriodicFields.Convolution.StoredKernel) = field_data(k.field)

# Multipliers and kernels are built over PLAIN storage (uncounted, as intended): `similar` on a
# CountingArray yields a plain Array, and the convenience constructor copies host wavenumbers into it.
const multipliers = FieldSpectralMultipliers(ScalarFieldSpectral(zeros(ComplexF64, shape0), grid))
const vector_plans = FieldTransformPlans(VectorFieldPhysical(zeros(grid.grid_size..., 3), grid),
                                         VectorFieldSpectral(zeros(ComplexF64, shape1), grid))
# Declared as kernels: a field of coefficients is no longer accepted in the kernel role, and the audit
# counts reads through the wrapped array either way.
const kernel = GBGPeriodicFields.Convolution.StoredKernel(ScalarFieldSpectral(ones(ComplexF64, shape0), grid))
const counted_kernel = () -> GBGPeriodicFields.Convolution.StoredKernel(
                               ScalarFieldSpectral(counting(ones(ComplexF64, shape0)), grid))


@testset "pass audit (element-traffic ledger)" begin

  # ---------------------------------------------------------------- M2 field algebra (physical)
  @testset "M2 algebra" begin
    a, b, d = vphys(), vphys(), vphys()
    audit(() -> add!(d, a, b), "add! vector",
      Traffic("a", carr(a), (3P, 0)), Traffic("b", carr(b), (3P, 0)), Traffic("dest", carr(d), (0, 3P)))
    audit(() -> subtract!(d, a, b), "subtract! vector",
      Traffic("a", carr(a), (3P, 0)), Traffic("b", carr(b), (3P, 0)), Traffic("dest", carr(d), (0, 3P)))
    audit(() -> combine!(d, 0.5, a, 2.0, b), "combine! (α·a + β·b)",
      Traffic("a", carr(a), (3P, 0)), Traffic("b", carr(b), (3P, 0)), Traffic("dest", carr(d), (0, 3P)))
    audit(() -> multiply!(d, 2.5, a), "multiply! by a real",
      Traffic("a", carr(a), (3P, 0)), Traffic("dest", carr(d), (0, 3P)))
    s = sphys(); parent(carr(s)) .+= 2        # nonzero divisor
    audit(() -> divide!(d, a, s), "divide! by a scalar field",
      Traffic("a", carr(a), (3P, 0)), Traffic("dest", carr(d), (0, 3P)),
      Traffic("divisor", carr(s), (P, 0)))                # fused: the divisor is read once per element
  end

  # ---------------------------------------------------------------- M3 field algebra (physical)
  @testset "M3 algebra" begin
    u, v, w, sd = vphys(), vphys(), vphys(), sphys()
    A, B = tphys(), tphys()
    audit(() -> dot!(sd, u, v), "dot!",
      Traffic("u", carr(u), (3P, 0)), Traffic("v", carr(v), (3P, 0)), Traffic("dest", carr(sd), (0, P)))
    audit(() -> cross!(w, u, v), "cross!",
      Traffic("u", carr(u), (3P, 0)),                     # fused one-pass (was 6P: two formulas per component)
      Traffic("v", carr(v), (3P, 0)),
      Traffic("dest", carr(w), (0, 3P)))
    audit(() -> mul!(w, A, u), "mul! tensor·vector",
      Traffic("A", carr(A), (9P, 0)),
      Traffic("u", carr(u), (3P, 0)),                     # fused one-pass (was 9P: read per output formula)
      Traffic("dest", carr(w), (0, 3P)))
    audit(() -> transpose!(B, A), "transpose!",
      Traffic("A", carr(A), (9P, 0)), Traffic("dest", carr(B), (0, 9P)))
    # The in-place storage move (decision 69). Its ideal is the simplest in this file — every source
    # element read once, every destination element written once — and that is exactly what makes it
    # worth pinning: the operation's entire claim is that it moves the data and allocates nothing, so
    # a regression here would be a second pass appearing where the point was to have one.
    audit(() -> adapt!(w, u), "adapt!",
      Traffic("source", carr(u), (3P, 0)), Traffic("dest", carr(w), (0, 3P)))
    audit(() -> sym!(B, A), "sym!",
      Traffic("A", carr(A), (9P, 0)),                     # fused one-pass (was 15P: off-diagonals fed two formulas)
      Traffic("dest", carr(B), (0, 9P)))
    audit(() -> tr!(sd, A), "tr!",
      Traffic("A", carr(A), (3P, 0)), Traffic("dest", carr(sd), (0, P)))
    audit(() -> det!(sd, A), "det!",
      Traffic("A", carr(A), (9P, 0)),                     # fused one-pass (was 15P: cofactor re-reads)
      Traffic("dest", carr(sd), (0, P)))
    # The siblings of the rows above. They were absent while add!/sym!/transpose!/det! were audited —
    # the family asymmetry the mutation audit flagged, and the reason completeness is now derived.
    audit(() -> skew!(B, A), "skew!",
      Traffic("A", carr(A), (9P, 0)), Traffic("dest", carr(B), (0, 9P)))
    audit(() -> dev!(B, A), "dev!",
      Traffic("A", carr(A), (9P, 0)),                     # at ideal: decision 39 fused the trace into a register
      Traffic("dest", carr(B), (0, 9P)))
    audit(() -> norm!(sd, u), "norm!",
      Traffic("u", carr(u), (3P, 0)), Traffic("dest", carr(sd), (0, P)))
  end

  # ---------------------------------------------------------------- map! (arbitrary φ via _fiberwise_pass!)
  # The adapter assembles each fiber from register reads and flattens the result, so map! rides the
  # fused executor at its ideal: every input component read once, every output written once — no φ can
  # inflate it. map!(det, …) has the same ledger as det! itself.
  @testset "map! (arbitrary φ)" begin
    u, v, w, sd = vphys(), vphys(), vphys(), sphys()
    A, B = tphys(), tphys()
    audit(() -> map!(det, sd, A), "map!(det) tensor→scalar",
      Traffic("A", carr(A), (9P, 0)), Traffic("dest", carr(sd), (0, P)))
    audit(() -> map!(x -> 2x, B, A), "map!(2x) tensor→tensor",
      Traffic("A", carr(A), (9P, 0)), Traffic("dest", carr(B), (0, 9P)))
    audit(() -> map!((a, b) -> a + b, w, u, v), "map!(+) multi-input vector",
      Traffic("u", carr(u), (3P, 0)), Traffic("v", carr(v), (3P, 0)), Traffic("dest", carr(w), (0, 3P)))
  end

  # ---------------------------------------------------------------- spectral differential operators
  @testset "spectral operators" begin
    φ, u = sspec(), vspec()
    sd, vd, td = sspec(), vspec(), tspec()
    audit(() -> gradient!(vd, φ, multipliers), "gradient! scalar→vector",
      Traffic("φ", carr(φ), (M, 0)),                    # fused one-pass (was 3M: one broadcast per output)
      Traffic("dest", carr(vd), (0, 3M)))
    audit(() -> gradient!(td, u, multipliers), "gradient! vector→tensor",
      Traffic("u", carr(u), (3M, 0)),                   # fused one-pass (each component once)
      Traffic("dest", carr(td), (0, 9M)))
    audit(() -> divergence!(sd, u, multipliers), "divergence! vector→scalar",
      Traffic("u", carr(u), (3M, 0)), Traffic("dest", carr(sd), (0, M)))
    audit(() -> divergence!(sd, u, multipliers, kernel), "divergence!∘kernel",
      Traffic("u", carr(u), (3M, 0)), Traffic("dest", carr(sd), (0, M)))
    audit(() -> divergence!(sd, u, multipliers, kernel, 0.5, 2.0), "divergence!∘kernel α/β",
      Traffic("u", carr(u), (3M, 0)), Traffic("dest", carr(sd), (M, M)))
    audit(() -> curl!(vd, u, multipliers), "curl!",
      Traffic("u", carr(u), (3M, 0)),                   # fused one-pass (was 6M: two formulas per component)
      Traffic("dest", carr(vd), (0, 3M)))
    # The inverse curl reads and writes exactly what the forward curl does — the extra reciprocal is
    # arithmetic on values already in registers, not traffic — so it sits at the same fused ideal.
    audit(() -> inverse_curl!(vd, u, multipliers), "inverse_curl!",
      Traffic("u", carr(u), (3M, 0)),
      Traffic("dest", carr(vd), (0, 3M)))
    audit(() -> symmetric_gradient!(td, u, multipliers), "symmetric_gradient!",
      Traffic("u", carr(u), (3M, 0)),                   # fused one-pass (was 15M: five formulas per component)
      Traffic("dest", carr(td), (0, 9M)))
    audit(() -> laplacian!(vd, u, multipliers), "laplacian! vector",
      Traffic("u", carr(u), (3M, 0)), Traffic("dest", carr(vd), (0, 3M)))
    audit(() -> inverse_laplacian!(vd, u, multipliers), "inverse_laplacian! vector",
      Traffic("u", carr(u), (3M, 0)), Traffic("dest", carr(vd), (0, 3M)))
  end

  # ---------------------------------------------------------------- the one-pass Helmholtz kernel
  @testset "helmholtz_projection! (the decision-32 one-pass kernel)" begin
    u, vd = vspec(), vspec()
    audit(() -> helmholtz_projection!(vd, u, multipliers), "helmholtz_projection!",
      Traffic("u", carr(u), (3M, 0)),                       # the decision-32 rewrite: 3, not 9
      Traffic("dest", carr(vd), (0, 3M)))                   # and β = 0 must not read the destination
    audit(() -> helmholtz_projection!(vd, u, multipliers, kernel), "helmholtz_projection!∘kernel",
      Traffic("u", carr(u), (3M, 0)), Traffic("dest", carr(vd), (0, 3M)))
    audit(() -> helmholtz_projection!(vd, u, multipliers, kernel, 0.5, 2.0),
      "helmholtz_projection!∘kernel α/β",
      Traffic("u", carr(u), (3M, 0)), Traffic("dest", carr(vd), (3M, 3M)))
    aliased = vspec()
    audit(() -> helmholtz_projection!(aliased, aliased, multipliers), "helmholtz_projection! aliased",
      Traffic("dest === source", carr(aliased), (3M, 3M)))
    g = counted_kernel()
    audit(() -> helmholtz_projection!(vd, u, multipliers, g), "helmholtz_projection! kernel read once per mode",
      Traffic("kernel", carr(g), (M, 0)))                   # the KA kernel reads ĝ once, not per component
  end

  # ------------------------------------------------ the weighted reductions (2026-09-30)
  @testset "weighted_inner (each coefficient read once; the two-field form reads each field once)" begin
    # The ideal is one read of every stored coefficient and no write. The one-field form read the
    # field TWICE until 2026-09-30, once as each operand of Re(f̂·conj ĝ) — found by a consumer's
    # traffic audit through its own forcing, the reductions having had no row here. The weights are
    # built over plain storage, so only the field's traffic is counted.
    s1, v1, v2 = sspec(), vspec(), vspec()
    band = spectral_band(multipliers, 1, 3)
    audit(() -> weighted_inner(s1, band), "weighted_inner scalar", Traffic("field", carr(s1), (M, 0)))
    audit(() -> weighted_inner(v1, band), "weighted_inner vector", Traffic("field", carr(v1), (3M, 0)))
    audit(() -> weighted_inner(v1, (band, band)), "weighted_inner vector, two weights one pass",
      Traffic("field", carr(v1), (3M, 0)))
    audit(() -> weighted_inner(v1, v2, band), "weighted_inner vector pair",
      Traffic("f", carr(v1), (3M, 0)), Traffic("g", carr(v2), (3M, 0)))
  end

  # ---------------------------------------------------------- the reality projector (decision 83)
  @testset "reality_projection! (the self-conjugate planes, each element once each way)" begin
    # The ideal is the plane area: every stored element of the zero plane and, the folded axis being
    # even here, of the Nyquist plane is read exactly once and written exactly once — a pair from its
    # owning side, a corner against itself — and nothing off those planes is touched.
    s1, v1 = sspec(), vspec()
    planes = iseven(field_grid(s1).grid_size[1]) ? 2 : 1
    plane = shape0[2] * shape0[3]
    audit(() -> reality_projection!(s1), "reality_projection! scalar",
      Traffic("field", carr(s1), (planes * plane, planes * plane)))
    audit(() -> reality_projection!(v1), "reality_projection! vector",
      Traffic("field", carr(v1), (3 * planes * plane, 3 * planes * plane)))
  end

  # ---------------------------------------------------------- the mean-free projector (decision 90)
  @testset "mean_free_projection! (one write per component, no read)" begin
    # The ideal is the fiber's component count: the zero coefficient of each component is written
    # once and nothing is read — a regression that walked the field would show up here as M.
    s1, v1, t1 = sspec(), vspec(), tspec()
    audit(() -> mean_free_projection!(s1), "mean_free_projection! scalar", Traffic("field", carr(s1), (0, 1)))
    audit(() -> mean_free_projection!(v1), "mean_free_projection! vector", Traffic("field", carr(v1), (0, 3)))
    audit(() -> mean_free_projection!(t1), "mean_free_projection! tensor", Traffic("field", carr(t1), (0, 9)))
  end

  # ------------------------------------------------ a kernel evaluated in place (decision 90)
  @testset "materialize_kernel! (each mode written once, the source read once)" begin
    destination = GBGPeriodicFields.Convolution.StoredKernel(sspec())
    g = counted_kernel()
    audit(() -> materialize_kernel!(destination, g), "materialize_kernel! stored",
      Traffic("kernel", carr(g), (M, 0)), Traffic("destination", carr(destination), (0, M)))
    radial_destination = GBGPeriodicFields.Convolution.StoredKernel(sspec())
    audit(() -> materialize_kernel!(radial_destination, spectral_band(multipliers, 1, 3)), "materialize_kernel! radial",
      Traffic("destination", carr(radial_destination), (0, M)))
  end

  # ------------------------------------------------- moving modes between resolutions (decision 85)
  @testset "embed_modes! / extract_modes! (the shared modes, and nothing of the fine field besides)" begin
    # The ideal is hand-counted from the geometry, which is the whole value of this row: the fine
    # field must show traffic proportional to the COARSE grid, so a regression that walked the fine
    # field — the failure this operation exists to avoid — would show up here as `M` rather than 6.
    #
    # Coarse grid (4, 3, 2) under the same box, stored shape (3, 3, 2). Per axis, the shared indices:
    #   folded axis: stores 0 … 2, and 2 is its Nyquist (the axis is even) → 2 of 3 shared
    #   axis 2 (N = 3, odd): no Nyquist mode exists → 3 of 3 shared
    #   axis 3 (N = 2, even): stores 0 and the Nyquist → 1 of 2 shared
    # so 2 × 3 × 1 = 6 shared modes per component.
    shared = 6
    coarse_grid = Grid3D((4, 3, 2), grid.domain_size)
    coarse_shape0 = F.field_spectral_shape(coarse_grid, layout, Val(0))
    coarse_shape1 = F.field_spectral_shape(coarse_grid, layout, Val(1))
    cs() = ScalarFieldSpectral(counting(randn(ComplexF64, coarse_shape0)), coarse_grid)
    cv() = VectorFieldSpectral(counting(randn(ComplexF64, coarse_shape1)), coarse_grid)

    fine_s, coarse_s = sspec(), cs()
    audit(() -> embed_modes!(fine_s, coarse_s), "embed_modes! scalar",
      Traffic("coarse", carr(coarse_s), (shared, 0)), Traffic("fine", carr(fine_s), (0, shared)))
    fine_v, coarse_v = vspec(), cv()
    audit(() -> embed_modes!(fine_v, coarse_v), "embed_modes! vector",
      Traffic("coarse", carr(coarse_v), (3shared, 0)), Traffic("fine", carr(fine_v), (0, 3shared)))

    fine_s2, coarse_s2 = sspec(), cs()
    audit(() -> extract_modes!(coarse_s2, fine_s2), "extract_modes! scalar",
      Traffic("fine", carr(fine_s2), (shared, 0)), Traffic("coarse", carr(coarse_s2), (0, shared)))
    fine_v2, coarse_v2 = vspec(), cv()
    audit(() -> extract_modes!(coarse_v2, fine_v2), "extract_modes! vector",
      Traffic("fine", carr(fine_v2), (3shared, 0)), Traffic("coarse", carr(coarse_v2), (0, 3shared)))

    # Accumulating reads the destination's shared modes as well, and still nothing else.
    fine_s3, coarse_s3 = sspec(), cs()
    audit(() -> embed_modes!(fine_s3, coarse_s3, 0.5, 1.0), "embed_modes! accumulate",
      Traffic("coarse", carr(coarse_s3), (shared, 0)), Traffic("fine", carr(fine_s3), (shared, shared)))
  end

  # ---------------------------------------------------------------- convolution family
  @testset "convolution family" begin
    f, a, b, d = vspec(), vspec(), vspec(), vspec()
    g = counted_kernel()
    audit(() -> convolve!(d, f, g), "convolve! vector",
      Traffic("f", carr(f), (3M, 0)), Traffic("dest", carr(d), (0, 3M)),
      Traffic("kernel", carr(g), (M, 0)))                 # fused: ĝ read once per mode (was 3M)
    audit(() -> convolve!(d, f, g, 0.5, 2.0), "convolve! α/β",
      Traffic("f", carr(f), (3M, 0)), Traffic("dest", carr(d), (3M, 3M)),
      Traffic("kernel", carr(g), (M, 0)))                 # fused: ĝ read once per mode (was 3M)
    # The axis-factored kernel (decision 50) carries NO field-sized stream — there is no kernel Traffic
    # row here because there is no kernel array to count, which is the point. What this pins is that the
    # source and destination stay at the fused ideal: swapping a stored kernel for the lazy per-axis
    # product must not push the executor into re-reading a source per output component.
    #
    # A caveat on the ledger, not on the operation: this file counts ELEMENT reads, not bytes. Per mode
    # the separable kernel reads one entry from each of three O(N) axis arrays where a stored kernel read
    # one entry from an O(N³) field, so by element count it is three reads against one. The win is in
    # bytes moved: the three axis arrays total kilobytes and stay resident, while the stored kernel is a
    # field-sized DRAM stream. The axis arrays are deliberately left uncounted rather than recorded as a
    # 3M "regression" the ledger would otherwise imply.
    separable = translation_kernel(multipliers, (0.3, -0.7, 1.1))
    audit(() -> convolve!(d, f, separable), "convolve! vector ∘ separable kernel",
      Traffic("f", carr(f), (3M, 0)), Traffic("dest", carr(d), (0, 3M)))
    audit(() -> convolve!(d, f, separable, 0.5, 2.0), "convolve! α/β ∘ separable kernel",
      Traffic("f", carr(f), (3M, 0)), Traffic("dest", carr(d), (3M, 3M)))

    audit(() -> exponential_convolve!(d, f, multipliers, -0.1), "exponential_convolve!",
      Traffic("f", carr(f), (3M, 0)), Traffic("dest", carr(d), (0, 3M)))
    w = ScalarFieldSpectral(counting(ones(ComplexF64, shape0)), grid)   # ŵ is a field, not a kernel
    audit(() -> exponential_convolve!(d, f, multipliers, -0.1, 0.01, w), "exponential_convolve! ŵ offset",
      Traffic("f", carr(f), (3M, 0)), Traffic("dest", carr(d), (0, 3M)),
      # 3M → M on 2026-08-30: the fiber hoist (IT item 2) retired this ledger's LAST holder — the
      # mode-loop now reads the offset field once per mode and reuses the factor across components,
      # exactly the fix the old note priced. Frozen at the fused ideal.
      Traffic("ŵ", carr(w), (M, 0)))
    # A radial offset (2026-10-01) is evaluated, not read: the source and destination are the whole
    # traffic, the same as the plain form, where the stored offset adds M reads.
    audit(() -> exponential_convolve!(d, f, multipliers, -0.1, 0.01, spectral_band(multipliers, 1, 3)),
      "exponential_convolve! radial offset",
      Traffic("f", carr(f), (3M, 0)), Traffic("dest", carr(d), (0, 3M)))
    audit(() -> exponential_convolve!(d, 0.3, a, 0.7, b, multipliers, -0.1),
      "exponential_convolve! two-operand",
      Traffic("a", carr(a), (3M, 0)), Traffic("b", carr(b), (3M, 0)), Traffic("dest", carr(d), (0, 3M)))
    audit(() -> combine!(d, 0.3, a, 0.7, b, g), "combine!∘kernel",
      Traffic("a", carr(a), (3M, 0)), Traffic("b", carr(b), (3M, 0)), Traffic("dest", carr(d), (0, 3M)),
      Traffic("kernel", carr(g), (M, 0)))                 # fused: ĝ read once per mode (was 3M)
  end

  # ---------------------------------------------------------------- reductions
  @testset "reductions" begin
    u, v = vphys(), vphys()
    A = tphys()
    audit(() -> inner(u, v), "inner physical (mixed)",
      Traffic("u", carr(u), (3P, 0)),                   # the fixed-tree dot seeds from its first element — no typing peek (decision 40)
      Traffic("v", carr(v), (3P, 0)))
    audit(() -> mean(u), "mean vector",
      Traffic("u", carr(u), (3P, 0)))                   # per-component tree sums — no peek (decision 40)
    audit(() -> maximum(norm, u), "maximum(norm, u) — fused mapped form",
      Traffic("u", carr(u), (3P, 0)))
    audit(() -> mean(det, A), "mean(det, A) — fused mapped form",
      Traffic("A", carr(A), (9P, 0)))                       # the fiber is gathered once per point
    fs = vspec()
    audit(() -> radial_spectrum(fs, multipliers), "radial_spectrum (fused binning)",
      Traffic("f", carr(fs), (3M, 0)))
    gs2 = vspec()
    audit(() -> radial_spectrum(fs, gs2, multipliers), "radial_spectrum co-spectrum",
      Traffic("f", carr(fs), (3M, 0)), Traffic("g", carr(gs2), (3M, 0)))
  end

  # ------------------------------------------------- radial correlation (its countable stages)
  # The transform interior is FFTW's, but the wrapper never reaches it: the power-spectrum build
  # writes a plain scratch (`similar` on a CountingArray yields an `Array`), so the public call
  # audits the input-side contract, and the fused physical binning kernel (decision 34) is audited
  # directly on its raw input.
  @testset "radial_correlation stages" begin
    f = vspec()
    audit(() -> radial_correlation(f, vector_plans), "radial_correlation input read",
      Traffic("f", carr(f), (3M, 0)))
    correlation_data = counting(randn(grid.grid_size..., 3))
    audit(() -> GBGPeriodicFields.Reductions._radial_average(grid, correlation_data, P),
      "_radial_average physical shell binning (decision-34 kernel)",
      Traffic("correlation field", correlation_data, (3P, 0)))
  end

  # ------------------------------------------------- point transfer (the gather)
  # Per-point stencil counts, exact: a CatmullRom (n = 1) gather reads (2n+2)³ = 64 field values
  # per point per component and writes one output slot per point per component; positions stay
  # plain (coordinate reads are three per point, by inspection of the kernel). The scatter waits on
  # atomics over the wrapper (see the header exclusions).
  @testset "interpolation gather" begin
    number_of_points = 10
    positions = hcat(2π .* rand(number_of_points), 4π .* rand(number_of_points),
                     6π .* rand(number_of_points))
    points = PointSet(positions)
    u = vphys()
    gathered = VectorPointValues(counting(zeros(number_of_points, 3)))
    stencil = 4^3                               # CatmullRom: n = 1 ⇒ (2n+2)³ nodes
    audit(() -> interpolate!(gathered, u, points, CatmullRom), "interpolate! CatmullRom gather",
      Traffic("field", carr(u), (3 * stencil * number_of_points, 0)),
      Traffic("output", point_values(gathered), (0, 3 * number_of_points)))
  end

  # ------------------------------------------------- base-space motion (decision 73)
  # The fused ideal is exact and small: a displacement reads the source coordinates once, each
  # section once, and writes the destination coordinates once; the torus arity fuses the wrap into
  # the same pass, so its counts are identical — that identity is what these rows pin. `wrap!`
  # reads and writes each coordinate exactly once.
  @testset "base-space motion" begin
    number_of_points = 10
    coordinate_count = 3 * number_of_points
    grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
    destination = PointSet(counting(zeros(number_of_points, 3)))
    source = PointSet(counting(rand(number_of_points, 3)))
    section_a = VectorPointValues(counting(randn(number_of_points, 3)))
    section_b = VectorPointValues(counting(randn(number_of_points, 3)))
    audit(() -> displace!(destination, source, (0.3, section_a), (0.7, section_b)),
          "displace! 2-term cover",
      Traffic("source", point_positions(source), (coordinate_count, 0)),
      Traffic("section a", point_values(section_a), (coordinate_count, 0)),
      Traffic("section b", point_values(section_b), (coordinate_count, 0)),
      Traffic("destination", point_positions(destination), (0, coordinate_count)))
    audit(() -> displace!(destination, source, grid, (0.3, section_a), (0.7, section_b)),
          "displace! 2-term torus (wrap fused)",
      Traffic("source", point_positions(source), (coordinate_count, 0)),
      Traffic("section a", point_values(section_a), (coordinate_count, 0)),
      Traffic("section b", point_values(section_b), (coordinate_count, 0)),
      Traffic("destination", point_positions(destination), (0, coordinate_count)))
    audit(() -> wrap!(destination, grid), "wrap!",
      Traffic("coordinates", point_positions(destination), (coordinate_count, coordinate_count)))
  end

end


# ---------------------------------------------------------------------------------------------
# Completeness (decision 53), derived from the export list rather than remembered. The exclusions
# below are the ones this file's header already argues for; anything else must have a row.
GBGCodingTools.TestHarness.traffic_completeness(GBGPeriodicFields,
    filter(m -> m !== GBGPeriodicFields, collect(PACKAGE_MODULES));
    exempt = Dict(
      :to_physical!          => "the transform interior is FFTW's, and FFT plans reject wrapped storage",
      :to_spectral!          => "same — the transform interior is out of scope (see the header)",
      :anterpolate!          => "the scatter accumulates through Atomix, which a wrapper array cannot provide (header)",
      :translation_kernel!   => "an O(N) per-axis rebuild, not field-shaped traffic",
      :point_traversal_order!       => "the counting sort histograms and places through Atomix, which a wrapper array cannot provide — the same reason `anterpolate!` is here; its allocation contract is guarded in test/allocations.jl and its result in test/point_traversal_order.jl",
      :copyto!               => "the broadcast interface: the field `copyto!` IS the `_assign!` route every audited operation writes through, measured through them rather than as a case of its own",
      :setindex!             => "the AbstractArray interface: a single-element write, not a field-shaped pass",
      :set_fft_threads!      => "a configuration setter, not a field operation",
      :set_threading_cutoff! => "a configuration setter, not a field operation",
    ))
