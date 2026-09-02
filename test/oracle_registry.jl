# Oracle provenance — the axis nobody enumerated (decision 55).
#
# WHY THIS FILE EXISTS. The suite's stated philosophy is "verify against independent ground truth,
# never against the code's own other path". Nothing enforced it. The mutation audit could not see the
# gap either, because it asks a different question — "would a defect be caught?" — and a RELATIONAL
# chain that terminates in an anchored reference does catch defects. So `weighted_inner` went its
# whole life with no direct value: every assertion compared it to `inner`, `laplacian`, `gradient` or
# `convolve`. Correct, and caught real mutations, but resting entirely on other operators.
#
# The distinction the suite lacked a name for:
#   :analytic     a closed form, derived independently of the package (∂ₓ sin x = cos x, ⟨sin²⟩ = ½)
#   :independent  a direct computation written in the test (a per-point loop, Σ|u|²/N, an O(M²) count)
#   :property     an invariant that pins the operation without computing it (adjointness, idempotence,
#                 a divergence-free result) — independent of any other package routine
#   :relational   compared ONLY against other package operations. Legitimate as a SECOND layer; as the
#                 only layer it means the operation is correct exactly insofar as its neighbours are
#   :structural   returns metadata or storage, not a value: nothing to have an oracle for
#
# WHAT THIS ENFORCES. Every public value-returning operation must appear below. A new operation fails
# this file until someone classifies it — which is the point: the classification is the moment to
# notice that an operation has no independent oracle, instead of discovering it a year later.

using Test
using GBGPeriodicFields
using Statistics
include("public_surface.jl")

# operation => (provenance, where the strongest oracle lives)
const ORACLE_PROVENANCE = Dict{Symbol, Tuple{Symbol, String}}(
  # ---- differential operators: closed forms over the asymmetric fixture family ----
  :gradient           => (:analytic, "generated_analytic.jl — ∂_{xⱼ}uᵢ per slot, all nine distinct"),
  :divergence         => (:analytic, "generated_analytic.jl — vector and tensor, closed form"),
  :curl               => (:analytic, "generated_analytic.jl — ε_ijk ∂_{xⱼ}u_k"),
  :laplacian          => (:analytic, "generated_analytic.jl — −q² per term"),
  :symmetric_gradient => (:analytic, "generated_analytic.jl — ½(∇u + ∇uᵀ) on an asymmetric fixture"),
  :inverse_laplacian  => (:analytic, "differentialoperators.jl — analytic round trip on a mean-free field"),
  :inverse_curl       => (:analytic, "differentialoperators.jl — the closed-form pair u = (sin y, sin z, sin x), w = ∇×u = (−cos z, −cos x, −cos y): the field is recovered from its own curl without the package computing either"),
  :helmholtz_projection => (:property, "adjointness.jl — idempotent, self-adjoint, divergence-annihilating"),

  # ---- transforms ----
  :to_spectral        => (:analytic, "fields.jl — coefficients vs the analytic Fourier series; round trip"),
  :to_physical        => (:analytic, "fields.jl — same, inverse direction"),

  # ---- fiberwise algebra: per-component references written in the test ----
  :dot                => (:independent, "fieldalgebra.jl — explicit Σ over components"),
  :cross              => (:independent, "fieldalgebra.jl — explicit Levi-Civita expansion"),
  :det                => (:independent, "fieldalgebra.jl — per-point LU oracle"),
  :tr                 => (:independent, "fieldalgebra.jl — explicit Σ of the diagonal"),
  :norm               => (:independent, "fieldalgebra.jl — explicit √Σ"),
  :sym                => (:independent, "fieldalgebra.jl — explicit ½(A + Aᵀ)"),
  :skew               => (:independent, "fieldalgebra.jl — explicit ½(A − Aᵀ)"),
  :dev                => (:independent, "fieldalgebra.jl — explicit A − tr(A)I/3"),
  :×                  => (:independent, "fieldalgebra.jl — the alias agrees with `cross`, whose oracle is the explicit expansion"),
  :⋅                  => (:independent, "fieldalgebra.jl — the alias agrees with `dot`, whose oracle is the explicit expansion"),

  # ---- reductions ----
  :inner              => (:analytic, "generated_analytic.jl — Σ A²/2; and reductions.jl Σ|u|²/N"),
  :l2norm             => (:analytic, "generated_analytic.jl — √(Σ A²/2)"),
  :weighted_inner     => (:analytic, "generated_analytic.jl — Dirichlet Σ(Aq)²/2 and two sharp bands"),
  :integral           => (:analytic, "reductions.jl — ∫c dx = c|Ω|; generated_analytic.jl — zero mean"),
  :radial_spectrum    => (:analytic, "reductions.jl — constant → E(0)=c², cos x → E(1)=½"),
  :radial_correlation => (:independent, "reductions.jl — a binned circshift autocorrelation"),
  :lpnorm             => (:independent, "reductions.jl — explicit (Σ|·|ᵖ/N)^{1/p}"),
  :reality_residual   => (:independent, "fields.jl — an elementwise walk of the self-conjugate planes, "
                                        * "written from |f̂(k) − conj(f̂(−k))| and sharing no code with "
                                        * "the implementation, which goes plane-at-a-time"),

  # ---- convolution and kernels ----
  :convolve           => (:independent, "convolution.jl — the circshift oracle for a whole-cell shift"),
  :translation_kernel => (:independent, "convolution.jl — circshift, and DirectDFT at displaced nodes"),
  :assignment_window  => (:analytic, "rdf.jl / convolution.jl — the ∏ sinc² closed form"),
  :spectral_cutoff    => (:analytic, "convolution.jl — the |k|² membership oracle"),
  :spectral_band      => (:analytic, "convolution.jl — the annular membership oracle"),
  :exponential_convolve => (:analytic, "convolution.jl — the single-mode eigenvalue e^c·cos x"),
  :radial_kernel      => (:analytic, "generated_analytic.jl / convolution.jl — σ evaluated per mode vs its values"),
  :materialize_kernel => (:independent, "convolution.jl — vs the explicit per-axis product"),
  :⋆                  => (:independent, "fieldalgebra.jl — the alias agrees with `convolve`; convolution.jl — the oracle"),

  # ---- grid ↔ point transfer ----
  :interpolate        => (:analytic, "transfer_spectral.jl — exact reconstruction of a band-limited field"),
  :anterpolate        => (:property, "interpolation_transfer.jl — the adjoint relation and conservation"),
  # An order is checked against what a permutation IS, not against another package operation: it must
  # be a bijection of 1:M, and the tile keys along it must be nondecreasing — the keys recomputed on
  # the host from the coordinates, so nothing in the chain runs the kernel that built them.
  :transfer_order     => (:analytic, "transfer_order.jl — a bijection, and nondecreasing against host-recomputed tile keys"),

  # ---- extensions of Base and Statistics generics ----
  # These are public operations that `names(GBGPeriodicFields)` cannot see, because the package
  # extends them rather than declaring them and deliberately does not re-export them. The field
  # arithmetic is in this class, so the four operators a user reaches for first were invisible to
  # every completeness guard until the domain was derived from method ownership.
  :+                  => (:independent, "fieldalgebra.jl — explicit per-component sums"),
  :-                  => (:independent, "fieldalgebra.jl — explicit per-component differences"),
  :*                  => (:independent, "fieldalgebra.jl — explicit scalar and contraction references"),
  :/                  => (:independent, "fieldalgebra.jl — explicit per-component quotients"),
  :transpose          => (:independent, "fieldalgebra.jl — explicit index swap"),
  :map                => (:independent, "fieldalgebra.jl — φ applied explicitly at every base point"),
  :mean               => (:analytic, "reductions.jl — ⟨sin⟩ = 0; generated_analytic.jl — zero mean"),
  :var                => (:analytic, "generated_analytic.jl — Σ A²/2 for a zero-mean fixture"),
  :std                => (:analytic, "reductions.jl — √⟨sin²⟩ = 1/√2 on a zero-mean field"),
  :cov                => (:independent, "reductions.jl — a per-point covariance reference"),
  :maximum            => (:independent, "reductions.jl — Julia's own maximum over the raw array"),
  :minimum            => (:independent, "reductions.jl — Julia's own minimum over the raw array"),
  :extrema            => (:independent, "reductions.jl — the pair oracle, plus the scalar-only absence"),

  :inv                => (:property, "convolution.jl — inv(g) ⋆ (g ⋆ f) == f, the deconvolution round trip"),

  # The `AbstractArray` and broadcast interface. Extended so fields interoperate with Julia's array
  # machinery; each returns storage or a shape, so there is no value to have an oracle for. They
  # appear here rather than being filtered because an interface method IS reachable by a user, and a
  # domain that quietly drops a class is the defect this whole file exists to prevent.
  (op => (:structural, "the AbstractArray/broadcast interface: returns storage or a shape") for op in
   (:axes, :copy, :eltype, :getindex, :length, :ndims, :size))...,

  # ---- structural: metadata, storage and configuration, with no value to have an oracle for ----
  (op => (:structural, "returns metadata or storage, not a computed value") for op in
   (:field_data, :field_grid, :field_layout, :field_scalar_type, :field_tensor_order, :fiber_shape,
    :npoints, :point_positions, :point_values, :point_value_tensor_order, :field_physical_shape,
    :field_spectral_shape, :similar_field, :similar_point_values, :threading_cutoff, :with_threading))...,
  (op => (:structural, "HDF5 persistence, covered by round-trip equality in hdf5.jl") for op in
   (:read_field, :read_points, :write_field, :write_points, :read_scheme, :write_scheme))...,

  # Moving between storage families. `adapt` is the identity on the mathematical object — it changes
  # where the storage lives and nothing else — so its oracle is a preservation property rather than a
  # computed value: the array compares equal elementwise, the element type is unchanged, and the grid,
  # layout, origin and tensor order all survive. Those are asserted directly against the original's
  # raw arrays and raw metadata, not through another package operation. `adapt_structure` is the
  # extension hook `adapt` dispatches to and shares the classification; it is listed rather than
  # filtered because it is reachable by a user writing their own adaptor.
  (op => (:property, "adapt.jl — storage family changes, everything else is preserved; driven on CPU " *
                     "by a custom adaptor, since adapting to the family one is already in is the identity")
     for op in (:adapt, :adapt_structure))...,
)

@testset "oracle provenance is classified for every public operation" begin
  public_ops = value_operations()
  unclassified = setdiff(public_ops, keys(ORACLE_PROVENANCE))
  isempty(unclassified) ||
    @error """a public operation has no recorded oracle provenance. Classify it — and if the honest
              answer is :relational, that is the finding: the operation is correct only insofar as the
              operations it is compared against are.""" unclassified
  @test isempty(unclassified)

  # A classification naming an operation that no longer exists is stale.
  @test isempty(setdiff(keys(ORACLE_PROVENANCE), public_ops))

  # Every classification must be one of the five kinds.
  @test all(p -> p[1] in (:analytic, :independent, :property, :relational, :structural),
            values(ORACLE_PROVENANCE))

  # The standing bar: no operation may rest on :relational coverage alone. This is currently empty,
  # and it is the assertion that keeps it empty — `weighted_inner` sat here unnoticed until 6434ad86.
  relational_only = sort([String(k) for (k, v) in ORACLE_PROVENANCE if v[1] === :relational])
  isempty(relational_only) ||
    @error "operations whose only oracle is other package operations" relational_only
  @test isempty(relational_only)
end


# The registry cites a file for every classification, and a citation nobody checks is a comment.
# Verifying that the cited file EXISTS and mentions the operation does not prove the assertion in it is
# genuinely analytic — that judgement stays human — but it does close the half that rots on its own: an
# entry surviving a test being moved, renamed or deleted. Cheap, mechanical, and it would have caught a
# stale citation at any point in this file's life.
@testset "every oracle citation names a file that exists and mentions the operation" begin
  test_directory = @__DIR__
  missing_file = Tuple{String, String}[]
  unmentioned = Tuple{String, String}[]
  for (operation, (provenance, where_it_lives)) in ORACLE_PROVENANCE
    provenance === :structural && continue          # no oracle, so no citation to check
    # The citation reads "<file>.jl — prose"; take the files it names.
    for token in eachmatch(r"[A-Za-z_0-9]+\.jl", where_it_lives)
      path = joinpath(test_directory, token.match)
      if !isfile(path)
        push!(missing_file, (String(operation), token.match))
        continue
      end
      occursin(String(operation), read(path, String)) ||
        push!(unmentioned, (String(operation), token.match))
    end
    # Every non-structural entry must cite at least one file, or it cites nothing at all.
    @test occursin(".jl", where_it_lives)
  end
  isempty(missing_file) || @error "oracle citations naming a file that does not exist" missing_file
  @test isempty(missing_file)
  isempty(unmentioned) || @error "oracle citations whose file never mentions the operation" unmentioned
  @test isempty(unmentioned)
end
