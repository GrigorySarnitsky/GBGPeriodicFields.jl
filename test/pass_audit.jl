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
using Statistics: mean                        # extended on sections in Reductions (not re-exported)
import KernelAbstractions

const PRINT_COUNTS = get(ENV, "PASS_AUDIT_PRINT", "0") == "1"


# ---------------------------------------------------------------- the counting harness

struct CountingArray{T, N} <: AbstractArray{T, N}
  data::Array{T, N}
  reads::Threads.Atomic{Int}
  writes::Threads.Atomic{Int}
end

counting(data::Array) = CountingArray(data, Threads.Atomic{Int}(0), Threads.Atomic{Int}(0))

Base.size(a::CountingArray) = size(a.data)
Base.IndexStyle(::Type{<:CountingArray}) = IndexLinear()
Base.parent(a::CountingArray) = a.data

Base.@propagate_inbounds function Base.getindex(a::CountingArray, i::Int)
  Threads.atomic_add!(a.reads, 1)
  return a.data[i]
end

Base.@propagate_inbounds function Base.setindex!(a::CountingArray, value, i::Int)
  Threads.atomic_add!(a.writes, 1)
  a.data[i] = value
  return a
end

# The KA launchers ask the storage for its backend; answer for the wrapper (a method on our own
# test-local type — no piracy).
KernelAbstractions.get_backend(a::CountingArray) = KernelAbstractions.get_backend(a.data)


# One array's row in an audited call: the frozen (reads, writes) asserted exactly, the fused ideal
# documented beside it, and a named holder required whenever frozen ≠ ideal.
struct Traffic
  role::String
  array::CountingArray
  frozen::NTuple{2, Int}
  ideal::NTuple{2, Int}
  holder::String
end

Traffic(role, array, frozen) = Traffic(role, array, frozen, frozen, "")


function audit(operation!, name::String, rows::Traffic...)
  foreach(r -> (r.array.reads[] = 0; r.array.writes[] = 0), rows)
  operation!()
  @testset "$name" begin
    for r in rows
      measured = (r.array.reads[], r.array.writes[])
      PRINT_COUNTS && println(rpad(name, 52), rpad(r.role, 14), "measured ", measured,
                              "  frozen ", r.frozen, "  ideal ", r.ideal)
      @test measured == r.frozen
      if r.frozen != r.ideal
        @test !isempty(r.holder)              # an above-ideal count must carry a named holder
      end
    end
  end
end


# ---------------------------------------------------------------- setup

# Mixed axis lengths catch index transpositions; even first axis exercises the Nyquist plane.
const grid = Grid3D((8, 6, 4), (2π, 4π, 6π))
const layout = RealFourierLayout()
const F = GBGPeriodicFields.Fields
const shape0 = F.spectral_field_shape(grid, layout, Val(0))
const shape1 = F.spectral_field_shape(grid, layout, Val(1))
const shape2 = F.spectral_field_shape(grid, layout, Val(2))
const M = prod(shape0[1:3])                   # spectral modes per component
const P = prod(grid.grid_size)                # physical points per component

sspec() = ScalarFieldSpectral(counting(randn(ComplexF64, shape0)), grid)
vspec() = VectorFieldSpectral(counting(randn(ComplexF64, shape1)), grid)
tspec() = TensorFieldSpectral{2}(counting(randn(ComplexF64, shape2)), grid)
sphys() = ScalarFieldPhysical(counting(randn(grid.grid_size...)), grid)
vphys() = VectorFieldPhysical(counting(randn(grid.grid_size..., 3)), grid)
tphys() = TensorFieldPhysical{2}(counting(randn(grid.grid_size..., 3, 3)), grid)

carr(f) = field_data(f)                       # the CountingArray behind a field

# Multipliers and kernels are built over PLAIN storage (uncounted, as intended): `similar` on a
# CountingArray yields a plain Array, and the convenience constructor copies host wavenumbers into it.
const multipliers = FieldSpectralMultipliers(ScalarFieldSpectral(zeros(ComplexF64, shape0), grid))
const vector_plans = FieldTransformPlans(VectorFieldPhysical(zeros(grid.grid_size..., 3), grid),
                                         VectorFieldSpectral(zeros(ComplexF64, shape1), grid))
const kernel = ScalarFieldSpectral(ones(ComplexF64, shape0), grid)
const counted_kernel = () -> ScalarFieldSpectral(counting(ones(ComplexF64, shape0)), grid)


@testset "pass audit (element-traffic ledger)" begin

  # ---------------------------------------------------------------- M2 field algebra (physical)
  @testset "M2 algebra" begin
    a, b, d = vphys(), vphys(), vphys()
    audit(() -> add!(d, a, b), "add! vector",
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
    audit(() -> sym!(B, A), "sym!",
      Traffic("A", carr(A), (9P, 0)),                     # fused one-pass (was 15P: off-diagonals fed two formulas)
      Traffic("dest", carr(B), (0, 9P)))
    audit(() -> tr!(sd, A), "tr!",
      Traffic("A", carr(A), (3P, 0)), Traffic("dest", carr(sd), (0, P)))
    audit(() -> det!(sd, A), "det!",
      Traffic("A", carr(A), (9P, 0)),                     # fused one-pass (was 15P: cofactor re-reads)
      Traffic("dest", carr(sd), (0, P)))
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
    audit(() -> helmholtz_projection!(vd, u, multipliers, g), "helmholtz kernel read once per mode",
      Traffic("kernel", carr(g), (M, 0)))                   # the KA kernel reads ĝ once, not per component
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
    audit(() -> exponential_convolve!(d, f, multipliers, -0.1), "exponential_convolve!",
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
      Traffic("u", carr(u), (3P + 1, 0), (3P, 0),
              "LinearAlgebra's generic dot peeks the first element to type its accumulator"),
      Traffic("v", carr(v), (3P + 1, 0), (3P, 0),
              "LinearAlgebra's generic dot peeks the first element to type its accumulator"))
    audit(() -> mean(u), "mean vector",
      Traffic("u", carr(u), (3P + 1, 0), (3P, 0),
              "the component reduction peeks one element to type its accumulator"))
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
      "physical shell binning (decision-34 kernel)",
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

end
