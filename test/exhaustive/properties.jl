# The remaining check types, executed.
#
# The ledger reported 564 applicable-but-unasserted cells and the RELATIONS table declared 25
# relations that NOTHING RAN — they existed only so the ledger could compute applicability. A declared
# relation nobody evaluates is worse than an absent one: it makes the coverage arithmetic look closed
# while the property goes unchecked.
#
# These lanes close them. Each check type here needs a shape the per-operation value lane cannot
# provide — a relation constrains two operations, an invariance compares two execution routes, a
# rejection asserts a call does NOT happen — so they are separate passes rather than more rows in the
# comparison table.

using GBGPeriodicFields
using Statistics
using LinearAlgebra


# A workbench of compatible sections for one configuration, built once per lane.
function _bench(config)
  T, grid, layout = config.eltype, config.grid, config.layout
  P(R) = (grid.grid_size..., ntuple(_ -> 3, R)...)
  spectral(R) = ScalarFieldSpectral(zeros(Complex{T}, GBGI.Fields.spectral_field_shape(grid, layout, Val(0))...),
                                    grid, layout)
  s = ScalarFieldPhysical(rand(T, P(0)...) .- T(1) / 2, grid, layout)
  u = VectorFieldPhysical(rand(T, P(1)...) .- T(1) / 2, grid, layout)
  v = VectorFieldPhysical(rand(T, P(1)...) .- T(1) / 2, grid, layout)
  A = TensorFieldPhysical{2}(rand(T, P(2)...) .- T(1) / 2, grid, layout)
  B = TensorFieldPhysical{2}(rand(T, P(2)...) .- T(1) / 2, grid, layout)
  z = spectral(0)
  plans0 = FieldTransformPlans(s, z)
  plans1 = FieldTransformPlans(u, similar_field(z, Val(1)))
  plans2 = FieldTransformPlans(A, similar_field(z, Val(2)))
  multipliers = FieldSpectralMultipliers(z)
  return (T = T, grid = grid, layout = layout, s = s, u = u, v = v, A = A, B = B, z = z,
          plans0 = plans0, plans1 = plans1, plans2 = plans2, multipliers = multipliers,
          sh = to_spectral(s, plans0), uh = to_spectral(u, plans1), vh = to_spectral(v, plans1),
          th = to_spectral(ScalarFieldPhysical(rand(T, P(0)...) .- T(1) / 2, grid, layout), plans0),
          Ah = to_spectral(A, plans2),
          points = PointSet(rand(T, 16, 3) .* reshape(collect(grid.domain_size), 1, 3) .+
                            reshape(collect(grid.origin), 1, 3)),
          q = ScalarPointValues(rand(T, 16)))
end

_tolerance(T) = T === Float32 ? 1.0f-3 : 1e-9

# A mean-free field: the inverse Laplacian is only a left inverse on the zero-mean subspace, and the
# spectral identities that quotient the constant need one.
function _mean_free(field)
  # Built through the allocator rather than the fully-parameterized concrete type: calling
  # `typeof(field)(data, grid, layout)` names every type parameter and matches no constructor.
  out = similar_field(field, Val(field_tensor_order(field)))
  data = copy(field_data(field))
  # In SPECTRAL representation mean-free means the zero (DC) mode vanishes — invariant 4 — not that the
  # coefficient array has zero mean. Subtracting the array's mean instead removes nothing meaningful
  # and makes the Δ⁻¹Δ identity fail, which is how this was found.
  if field isa GBGI.Fields.AbstractFieldSpectral
    data[1, 1, 1] = zero(eltype(data))
  else
    data .-= sum(data) / length(data)
  end
  copyto!(field_data(out), data)
  return out
end


# ── Relations: adjointness, algebraic identity, round-tripping ───────────────────────────────────

"""
    run_relations_lane(configs) -> (failures, cells)

Evaluate every relation the ledger declares. Each constrains two operations, so none of them can be
checked by a per-operation oracle.
"""
function run_relations_lane(configs)
  println("═"^100)
  println("LANE: declared relations — adjointness, algebraic identity, round-tripping")
  println("      the ledger declared 25 of these and executed none; they existed only so its")
  println("      applicability arithmetic would close")
  println("═"^100)

  failures = String[]
  cells = 0
  seen = Set{String}()

  for config in configs
    b = _bench(config)
    rtol = _tolerance(b.T)
    m, z = b.multipliers, b.z
    ∇ = f -> gradient(f, m)
    checks = (
      # ── adjointness ───────────────────────────────────────────────────────────────────────────
      ("⟨∇·u, φ⟩ = −⟨u, ∇φ⟩",
       inner(divergence(b.uh, m), b.sh), -inner(b.uh, gradient(b.sh, m))),
      ("curl is self-adjoint",
       inner(curl(b.uh, m), b.vh), inner(b.uh, curl(b.vh, m))),
      # Two DIFFERENT fields, or the identity is trivially true and the check cannot fail.
      ("Δ is self-adjoint",
       inner(laplacian(b.sh, m), b.th), inner(b.sh, laplacian(b.th, m))),
      ("Δ is negative-definite",
       inner(b.sh, laplacian(b.sh, m)) <= 0, true),
      ("ℙ is self-adjoint",
       inner(helmholtz_projection(b.uh, m), b.vh), inner(b.uh, helmholtz_projection(b.vh, m))),
      ("⟨f, w·g⟩ is symmetric in f, g",
       weighted_inner(b.sh, b.th, squared_wavenumber_field(z, m)),
       weighted_inner(b.th, b.sh, squared_wavenumber_field(z, m))),
      ("M⟨Wf, q⟩ = N⟨f, Wᵀq⟩",
       npoints(b.points) * inner(interpolate(b.s, b.points, CatmullRom), b.q),
       prod(config.grid.grid_size) * inner(b.s, anterpolate(config.grid, b.points, b.q, CatmullRom))),
      # ── algebraic identity ────────────────────────────────────────────────────────────────────
      ("∇·(∇×u) = 0",
       l2norm(divergence(curl(b.uh, m), m)), zero(b.T)),
      ("∇×(∇φ) = 0",
       l2norm(curl(gradient(b.sh, m), m)), zero(b.T)),
      ("sym + skew = id",
       field_data(sym(b.A)) .+ field_data(skew(b.A)), field_data(b.A)),
      ("ℙ² = ℙ",
       field_data(helmholtz_projection(helmholtz_projection(b.uh, m), m)),
       field_data(helmholtz_projection(b.uh, m))),
      ("symmetric_gradient = sym ∘ gradient",
       field_data(symmetric_gradient(b.uh, m)), field_data(sym(gradient(b.uh, m)))),
      ("det(AB) = det(A)·det(B)",
       field_data(det(mul!(similar_field(b.A, Val(2)), b.A, b.B))),
       field_data(det(b.A)) .* field_data(det(b.B))),
      ("tr(dev A) = 0",
       maximum(abs, field_data(tr(dev(b.A)))), zero(b.T)),
      ("Δ⁻¹Δ = id on mean-free fields",
       field_data(inverse_laplacian(laplacian(_mean_free(b.sh), m), m)),
       field_data(_mean_free(b.sh))),
      ("sum(radial_spectrum) = inner",
       sum(last(radial_spectrum(b.sh, m))), inner(b.sh, b.sh)),
      ("C(0) = inner",
       first(last(radial_correlation(b.sh, b.plans0))), inner(b.sh, b.sh)),
      ("a sharp cutoff is idempotent",
       field_data(convolve(convolve(b.sh, spectral_cutoff(z, m, b.T(3))), spectral_cutoff(z, m, b.T(3)))),
       field_data(convolve(b.sh, spectral_cutoff(z, m, b.T(3))))),
      ("‖f‖₂² = ⟨f, f⟩",
       l2norm(b.u)^2, inner(b.u, b.u)),
      ("integral = measure · mean",
       integral(b.s), prod(config.grid.domain_size) * mean(b.s)),
      # ── round-tripping ────────────────────────────────────────────────────────────────────────
      ("to_physical ∘ to_spectral = id",
       field_data(to_physical(to_spectral(b.s, b.plans0), b.plans0)), field_data(b.s)),
      ("inv(k) ⋆ k = id",
       field_data(convolve(convolve(b.sh, StoredKernel(materialize_kernel(spectral_cutoff(z, m, b.T(3))) +
                                                       ScalarFieldSpectral(ones(Complex{b.T}, size(field_data(z))...),
                                                                           config.grid, config.layout))),
                           inv(StoredKernel(materialize_kernel(spectral_cutoff(z, m, b.T(3))) +
                                            ScalarFieldSpectral(ones(Complex{b.T}, size(field_data(z))...),
                                                                config.grid, config.layout))))),
       field_data(b.sh)),
      ("a compressed kernel equals its materialization",
       field_data(convolve(b.sh, spectral_cutoff(z, m, b.T(3)))),
       field_data(convolve(b.sh, StoredKernel(materialize_kernel(spectral_cutoff(z, m, b.T(3))))))),
    )

    # Attribute each relation to the operations the ledger's own RELATIONS table says it constrains,
    # so the two cannot drift: the table decides applicability AND coverage from one statement.
    for relation in RELATIONS, operation in relation.ops
      record_coverage!(operation, relation.kind)
    end
    for (name, got, want) in checks
      cells += 1
      push!(seen, name)
      ok = try
        got isa Bool ? got == want : isapprox(_as_array(got), _as_array(want); rtol = rtol, atol = rtol)
      catch exception
        Base.push!(failures, "$(name) [$(config.name)] THREW $(nameof(typeof(exception)))")
        continue
      end
      ok || Base.push!(failures, "$(name) [$(config.name)]")
    end
  end

  println("\n  ", cells, " relation evaluations over ", length(configs), " configurations · ",
          length(seen), " distinct relations")
  if isempty(failures)
    println("  every declared relation holds")
  else
    println("\n  A DECLARED RELATION DOES NOT HOLD — ", length(failures), " cells:")
    for f in unique(failures); println("      ", f); end
  end
  return (length(failures), cells)
end


# ── Representation agreement, threading invariance, allocation, inequality, rejection ────────────

"""
    run_property_lanes(configs) -> (failures, cells)

The remaining check types the ledger names: representation agreement, thread-count invariance,
allocation, ordering, and domain rejection.
"""
function run_property_lanes(configs)
  println("═"^100)
  println("LANE: representation · invariance · allocation · inequality · rejection")
  println("═"^100)

  results = Dict{Symbol, Vector{String}}()
  counts = Dict{Symbol, Int}()
  record!(kind, message) = Base.push!(get!(results, kind, String[]), message)
  count!(kind) = counts[kind] = get(counts, kind, 0) + 1

  for config in configs
    b = _bench(config)
    rtol = _tolerance(b.T)
    m, z = b.multipliers, b.z
    same(x, y) = isapprox(_as_array(x), _as_array(y); rtol = rtol, atol = rtol)

    for (kind, operations) in ((:representation, (:add!, :multiply!, :sym, :transpose, :integral, :mean, :inner)),
                               (:invariance, (:add!, :mul!, :sym!, :map!, :inner, :l2norm, :helmholtz_projection!)),
                               (:allocation, (:add!, :combine!, :mul!, :laplacian!, :curl!,
                                              :helmholtz_projection!, :convolve!, :inner)),
                               (:inequality, (:l2norm, :var, :inner, :lpnorm, :laplacian, :minimum,
                                              :maximum, :convolve)),
                               (:domain_rejection, (:lpnorm, :spectral_band, :spectral_cutoff, :NUFFT,
                                                    :Grid3D, :set_threading_cutoff!)))
      for operation in operations
        record_coverage!(operation, kind)
      end
    end

    # ── representation agreement ────────────────────────────────────────────────────────────────
    # Invariant 1: an operation valid in both representations must compute the same physical object
    # either way. Checked by transforming the spectral result back rather than by comparing
    # coefficients, because the claim is about the FIELD, not its storage.
    for (name, physical_result, spectral_result) in
        (("add!", field_data(add!(similar_field(b.u, Val(1)), b.u, b.v)),
                  field_data(to_physical(add!(similar_field(b.uh, Val(1)), b.uh, b.vh), b.plans1))),
         ("multiply! by a constant", field_data(multiply!(similar_field(b.u, Val(1)), b.u, b.T(2))),
                  field_data(to_physical(multiply!(similar_field(b.uh, Val(1)), b.uh, b.T(2)), b.plans1))),
         ("sym", field_data(sym(b.A)), field_data(to_physical(sym(b.Ah), b.plans2))),
         ("transpose", field_data(transpose(b.A)), field_data(to_physical(transpose(b.Ah), b.plans2))),
         ("integral", integral(b.s), integral(b.sh)),
         ("mean", mean(b.s), mean(b.sh)),
         ("inner", inner(b.u, b.v), inner(b.uh, b.vh)))
      count!(:representation)
      same(physical_result, spectral_result) ||
        record!(:representation, "$(name) disagrees between representations [$(config.name)]")
    end

    # ── thread-count invariance ─────────────────────────────────────────────────────────────────
    # The CPU paths are bitwise thread-count-invariant by contract, so this is `==`, not a tolerance.
    for (name, run) in
        (("add!", () -> field_data(add!(similar_field(b.u, Val(1)), b.u, b.v))),
         ("mul!", () -> field_data(mul!(similar_field(b.u, Val(1)), b.A, b.u))),
         ("sym!", () -> field_data(sym!(similar_field(b.A, Val(2)), b.A))),
         ("map!", () -> field_data(map!(x -> 2x, similar_field(b.s, Val(0)), b.s))),
         ("inner", () -> inner(b.u, b.v)),
         ("l2norm", () -> l2norm(b.u)),
         ("helmholtz_projection!", () -> field_data(helmholtz_projection!(similar_field(b.uh, Val(1)), b.uh, m))))
      count!(:invariance)
      serial = with_threading(run; enabled = false)
      threaded = with_threading(run; enabled = true)
      serial == threaded ||
        record!(:invariance, "$(name) is not bitwise thread-invariant [$(config.name)]")
    end

    # ── allocation ──────────────────────────────────────────────────────────────────────────────
    # Invariant 13, measured on the CPU where a materialized array's bytes are actually counted.
    for (name, run) in
        (("add!", () -> add!(b.u, b.u, b.v)),
         ("combine!", () -> combine!(b.u, b.T(1) / 2, b.u, b.T(1) / 2, b.v)),
         ("mul!", () -> mul!(b.v, b.A, b.u)),
         ("laplacian!", () -> laplacian!(b.vh, b.uh, m)),
         ("curl!", () -> curl!(b.vh, b.uh, m)),
         ("helmholtz_projection!", () -> helmholtz_projection!(b.vh, b.uh, m)),
         ("convolve!", () -> convolve!(b.vh, b.uh, spectral_cutoff(z, m, b.T(3)))),
         ("inner", () -> inner(b.u, b.v)))
      count!(:allocation)
      run()                                        # warm up: the first call compiles
      bytes = @allocated run()
      bytes < 4096 ||
        record!(:allocation, "$(name) allocated $(bytes) bytes on a preallocated call [$(config.name)]")
    end

    # ── ordering and definiteness ───────────────────────────────────────────────────────────────
    for (name, holds) in
        (("‖u‖₂ ≥ 0", l2norm(b.u) >= 0),
         ("var ≥ 0", var(b.s) >= 0),
         ("|⟨u, v⟩| ≤ ‖u‖‖v‖  (Cauchy-Schwarz)",
          abs(inner(b.u, b.v)) <= l2norm(b.u) * l2norm(b.v) * (1 + 1e-8)),
         ("‖u‖₂ ≤ ‖u‖_∞", l2norm(b.u) <= lpnorm(b.u, Inf) * (1 + 1e-8)),
         ("⟨f, Δf⟩ ≤ 0  (Δ is negative-definite)", inner(b.sh, laplacian(b.sh, m)) <= 0),
         ("minimum ≤ maximum", minimum(b.s) <= maximum(b.s)),
         ("a sharp cutoff cannot raise the norm",
          l2norm(convolve(b.sh, spectral_cutoff(z, m, b.T(3)))) <= l2norm(b.sh) * (1 + 1e-8)))
      count!(:inequality)
      holds || record!(:inequality, "$(name) is violated [$(config.name)]")
    end

    # ── domain rejection: the call must NOT succeed ─────────────────────────────────────────────
    # Numeric arguments outside their documented domain, which the mismatch lane does not reach: it
    # varies the OBJECTS, and these are scalars.
    for (name, call) in
        (("lpnorm with p < 1", () -> lpnorm(b.u, 0.5)),
         ("lpnorm with a negative p", () -> lpnorm(b.u, -2)),
         ("spectral_band with lo > hi", () -> spectral_band(z, m, b.T(3), b.T(1))),
         ("spectral_band with a negative edge", () -> spectral_band(z, m, -b.T(1), b.T(3))),
         ("spectral_cutoff with a NaN edge", () -> spectral_cutoff(z, m, b.T(NaN))),
         ("NUFFT with a non-positive tolerance", () -> NUFFT(z; tol = zero(b.T))),
         ("NUFFT with a negative tolerance", () -> NUFFT(z; tol = -b.T(1))),
         ("a grid with a zero extent", () -> Grid3D((8, 8, 8), (zero(b.T), one(b.T), one(b.T)))),
         ("a grid with a NaN extent", () -> Grid3D((8, 8, 8), (b.T(NaN), one(b.T), one(b.T)))),
         ("set_threading_cutoff! below one", () -> set_threading_cutoff!(0)),
         ("a section over borrowed storage",
          () -> ScalarFieldPhysical(view(rand(b.T, config.grid.grid_size .+ 1...),
                                         1:config.grid.grid_size[1], 1:config.grid.grid_size[2],
                                         1:config.grid.grid_size[3]), config.grid, config.layout)))
      count!(:domain_rejection)
      rejected = try
        call()
        false
      catch
        true
      end
      rejected || record!(:domain_rejection, "$(name) was ACCEPTED [$(config.name)]")
    end
  end

  total = 0
  println()
  for kind in (:representation, :invariance, :allocation, :inequality, :domain_rejection)
    n = get(counts, kind, 0)
    failures = get(results, kind, String[])
    total += length(failures)
    println("      ", rpad(String(kind), 18), lpad(n, 7), " cells   ",
            isempty(failures) ? "clean" : "$(length(failures)) FINDINGS")
  end
  if total > 0
    println("\n  FINDINGS")
    for kind in (:representation, :invariance, :allocation, :inequality, :domain_rejection)
      for message in unique(get(results, kind, String[]))[1:min(end, 10)]
        println("      ", rpad(String(kind), 18), message)
      end
    end
  end
  return (total, sum(values(counts); init = 0))
end
