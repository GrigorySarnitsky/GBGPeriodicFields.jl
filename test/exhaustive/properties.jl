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
using Random


# A workbench of compatible sections for one configuration, built once per lane.
function _bench(config)
  T, grid, layout = config.eltype, config.grid, config.layout
  # The configuration's thread setting applies to the fixtures every lane built from this workbench.
  set_threading_cutoff!(config.threaded ? 1 : typemax(Int))
  Random.seed!(config.seed)          # the configuration's seed, not the global stream's position
  P(R) = (grid.grid_size..., ntuple(_ -> 3, R)...)
  spectral() = ScalarFieldSpectral(zeros(Complex{T}, GBGI.Fields.spectral_field_shape(grid, layout, Val(0))...),
                                   grid, layout)
  s = ScalarFieldPhysical(rand(T, P(0)...) .- T(1) / 2, grid, layout)
  u = VectorFieldPhysical(rand(T, P(1)...) .- T(1) / 2, grid, layout)
  v = VectorFieldPhysical(rand(T, P(1)...) .- T(1) / 2, grid, layout)
  A = TensorFieldPhysical{2}(rand(T, P(2)...) .- T(1) / 2, grid, layout)
  B = TensorFieldPhysical{2}(rand(T, P(2)...) .- T(1) / 2, grid, layout)
  z = spectral()
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

"""
    single_allocated(operation!, arguments...) -> Int

Bytes allocated by one call, measured behind a FUNCTION BARRIER.

Measuring `@allocated run()` where `run` closes over this lane's workbench charges the operation for
the enclosing scope's boxing — the workbench is a NamedTuple carrying a type parameter, so its locals
are not concrete. `convolve!` measured 1232 bytes that way and 128 at top level. The sequence lane hit
the same thing and documents the same fix.
"""
@noinline function single_allocated(operation!::F, arguments::Vararg{Any, N}) where {F, N}
  operation!(arguments...)                       # warm up: the first call compiles
  return @allocated operation!(arguments...)
end

# The magnitude a comparison should be judged against. For a relation whose expected value is zero
# This is the DEFAULT, used where a relation's two sides have a real magnitude. It must not be used for
# a relation whose expected value is exactly zero: there both sides ARE the residual, so the scale
# collapses to `eps(Float32)` and the tolerance to ~1e-18, failing every such relation in every
# configuration — 132 cells a run, none of them a defect. Those relations carry an explicit scale
# instead, the magnitude of the same operation on data where it does not vanish. Flooring at 1.0 was
# the other tempting fix and is wrong in the opposite direction: it gave `atol = 1e-3` on Float32,
# passing a violation worth 0.3% of the field norm.
_scale(want, got) = max(maximum(abs, _as_array(want); init = 0.0),
                        maximum(abs, _as_array(got); init = 0.0), eps(Float32))

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
    # ALL fiber components of the DC mode. `data[1,1,1]` on a 4-D or 5-D array is partial linear
    # indexing and reaches only the first component — latent today (only a scalar field is passed) and
    # wrong the moment one is not.
    selectdim(reshape(data, size(data, 1), size(data, 2), size(data, 3), :), 1, 1)[1, 1, :] .= 0
  else
    data .-= sum(data) / length(data)
  end
  copyto!(field_data(out), data)
  return out
end


# ── Relations: adjointness, algebraic identity, round-tripping ───────────────────────────────────

# Every lane that calls `_bench` must put the cutoff back: `_bench` pins it per configuration and the
# last configuration is `threaded = true`, so the lanes were leaving it at 1 for whatever ran next.
"""
    results_identical(a, b) -> Bool

The thread-invariance lane's comparison: bitwise, and NaN-safe.

`==` here was the same NaN class `checks.jl` fixed twice and `sequences.jl` received — missed because
the self-check extension that was meant to hold every lane to it never reached the property lanes.
"""
results_identical(a, b) = reproduces(a, b)


"""
    representations_agree(physical_result, spectral_result, rtol) -> Bool, or the exception type

The representation-agreement lane's comparison, extracted for the same reason.
"""
representations_agree(physical_result, spectral_result, rtol) =
  comparison_outcome() do
    isapprox(_as_array(physical_result), _as_array(spectral_result); rtol = rtol, atol = rtol)
  end


"""
    relation_holds(name, got, want, rtol, T) -> Bool, or the exception type on a throw

The relations lane's comparison step, extracted so `selfcheck.jl` can drive it against a deliberately
false triple.

The self-check proved that each of the five UNIVERSAL checks can fire and never touched the relations
lane, the value lane or the property lanes — so "a check that cannot fire is worse than none" was
enforced for one lane of nine. This is the seam that lets the others be held to it too.
"""
function relation_holds(name, got, want, rtol, T, scale = nothing)
  return comparison_outcome() do
    got isa Bool ? got == want :
      isapprox(_as_array(got), _as_array(want);
               rtol = rtol,
               atol = _tolerance(T) * (scale === nothing ? _scale(want, got) : scale))
  end
end


function _with_restored_cutoff(body)
  entry = threading_cutoff()
  try
    return body()
  finally
    set_threading_cutoff!(entry)
  end
end


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
      ("Δ is self-adjoint, negative-definite",
       inner(laplacian(b.sh, m), b.th), inner(b.sh, laplacian(b.th, m))),
      ("Δ is self-adjoint, negative-definite (definiteness)",
       inner(b.sh, laplacian(b.sh, m)) <= 0, true),
      ("ℙ is self-adjoint",
       inner(helmholtz_projection(b.uh, m), b.vh), inner(b.uh, helmholtz_projection(b.vh, m))),
      ("⟨f, w·g⟩ symmetric in f, g",
       weighted_inner(b.sh, b.th, materialize_kernel(radial_kernel(identity, m))),
       weighted_inner(b.th, b.sh, materialize_kernel(radial_kernel(identity, m)))),
      ("M⟨Wf, q⟩ = N⟨f, Wᵀq⟩",
       npoints(b.points) * inner(interpolate(b.s, b.points, CatmullRom), b.q),
       # The scatter destination must CARRY THE CONFIG'S LAYOUT. `anterpolate(grid, …)` builds a
       # default-layout field, and on a permuted-fold configuration that made this row `inner` a
       # fold2 field with a fold1 one — two different contexts, which every pairwise operation
       # refuses and `inner` now does too (the peer-rejection gate found `inner` was the one
       # exception, 2026-08-29). The lane conflated the contexts, not the package.
       prod(config.grid.grid_size) *
         inner(b.s, anterpolate!(GBGI.Fields.ScalarFieldPhysical(zeros(b.T, config.grid.grid_size...),
                                                                 config.grid, config.layout),
                                 b.points, b.q, CatmullRom))),
      # ── algebraic identity ────────────────────────────────────────────────────────────────────
      ("∇·(∇×u) = 0",
       l2norm(divergence(curl(b.uh, m), m)), zero(b.T), l2norm(divergence(b.uh, m))),
      ("∇×(∇φ) = 0",
       l2norm(curl(gradient(b.sh, m), m)), zero(b.T), l2norm(curl(b.uh, m))),
      # Each side against its INDEPENDENT reference. `_sym_values` and `_skew_values` are stamped from
      # one formula builder over the same nine arguments, so their sum is `A` by algebra whatever the
      # formula computes — the identity survives a wrong transpose convention entirely.
      ("sym + skew = id",
       field_data(sym(b.A)) .+ field_data(skew(b.A)),
       ref_sym(field_data(b.A)) .+ ref_skew(field_data(b.A))),
      ("ℙ² = ℙ",
       field_data(helmholtz_projection(helmholtz_projection(b.uh, m), m)),
       field_data(helmholtz_projection(b.uh, m))),
      ("symmetric_gradient = sym∘gradient",
       field_data(symmetric_gradient(b.uh, m)), field_data(sym(gradient(b.uh, m)))),
      ("det(AB) = det(A)det(B)",
       field_data(det(mul!(similar_field(b.A, Val(2)), b.A, b.B))),
       field_data(det(b.A)) .* field_data(det(b.B))),
      # `dev`'s internal trace subtraction reuses `tr`'s own formula builder, so this is zero because
      # two call sites share one formula, not because either is right. Checked against the references.
      ("tr(dev A) = 0",
       maximum(abs, field_data(tr(dev(b.A)))),
       maximum(abs, ref_trace(ref_dev(field_data(b.A)))),
       maximum(abs, field_data(tr(b.A)))),          # the trace where it does NOT vanish
      ("Δ⁻¹Δ = id on mean-free fields",
       field_data(inverse_laplacian(laplacian(_mean_free(b.sh), m), m)),
       field_data(_mean_free(b.sh))),
      # Against the REFERENCE, like `‖·‖₂²` and `integral = measure · mean` beside it. Comparing to the
      # package's own `inner` let a shared Parseval-weight or 1/N² defect cancel on both sides.
      ("sum(radial_spectrum) = inner",
       sum(last(radial_spectrum(b.sh, m))),
       ref_spectral_inner(field_data(b.sh), field_data(b.sh), config.grid, config.layout, 0)),
      ("C(0) = inner",
       first(last(radial_correlation(b.sh, b.plans0))),
       ref_spectral_inner(field_data(b.sh), field_data(b.sh), config.grid, config.layout, 0)),
      ("cutoff is idempotent",
       field_data(convolve(convolve(b.sh, spectral_cutoff(m, b.T(3))), spectral_cutoff(m, b.T(3)))),
       field_data(convolve(b.sh, spectral_cutoff(m, b.T(3))))),
      # Against the REFERENCE, not against `inner`: `l2norm(s) = sqrt(inner(s, s))` by definition
      # (src/Reductions.jl), so comparing the two was `sqrt(inner)^2` against `inner` and no defect in
      # `inner` could break it — while crediting both operations with identity coverage.
      ("‖·‖₂² = inner(f, f)",
       l2norm(b.u)^2, ref_inner(field_data(b.u), field_data(b.u), 1)),
      # Against the REFERENCE, for the same reason `‖·‖₂²` above it was: `integral` and `mean` both call
      # `_tree_sum` and differ only by `_cell_measure` vs `1/_base_count`, and `Grid3D` enforces
      # `grid_spacing ≈ domain_size ./ grid_size` — so the comparison collapsed to a metadata identity
      # that holds for any `f` and could not see a defect in the shared reduction. The fix applied to
      # the neighbouring relation was never carried here.
      ("integral = measure · mean",
       integral(b.s), only(ref_integral(field_data(b.s), 0, config.grid))),
      # ── round-tripping ────────────────────────────────────────────────────────────────────────
      ("to_physical ∘ to_spectral = id",
       field_data(to_physical(to_spectral(b.s, b.plans0), b.plans0)), field_data(b.s)),
      # A non-vanishing kernel, so the reciprocal exists: the sharp mask plus one, in the stored class.
      # `materialize_kernel` returns a `StoredKernel` now (decision 60), so the arithmetic is done on
      # the field it wraps and the result is declared a kernel once.
      ("inv(k) ⋆ k = id",
       let invertible = StoredKernel(
             ScalarFieldSpectral(GBGPeriodicFields.Convolution._kernel_data(
                                   materialize_kernel(spectral_cutoff(m, b.T(3)))) .+
                                 one(Complex{b.T}),
                                 config.grid, config.layout))
         field_data(convolve(convolve(b.sh, invertible), inv(invertible)))
       end,
       field_data(b.sh)),
      # Declared in the ledger's RELATIONS table and evaluated nowhere until now, while its two
      # operations were reported as covered for `identity`.
      # Declared in RELATIONS and evaluated nowhere until now. Compared through the raw arrays, not by
      # `==` on the sections, so a metadata-only difference is visible as a value difference too.
      # Guarded by `HDF5_AVAILABLE` at the ENTRY, not inside the value: the `? … : field_data(b.u)`
      # fallback made both sides the same object, so without HDF5 these two passed by identity while
      # still crediting all four persistence operations with round-trip coverage — in exactly the GPU
      # environments the README tells you to run.
      # Contributing a PASSING CELL when the dependency is absent is what the design forbids; the value
      # lane handles the same situation by contributing zero comparisons. These two now yield a sentinel
      # the loop drops, so the relation is reported unevaluated rather than tallied as holding.
      (HDF5_AVAILABLE ? ("read_field ∘ write_field = id",
        begin
          path = joinpath(mktempdir(), "relation.h5")
          HDF5.h5open(f -> write_field(f, "u", b.u), path, "w")
          field_data(HDF5.h5open(f -> read_field(f, "u"), path, "r"))
        end, field_data(b.u)) :
       (:skip, nothing, nothing)),
      (HDF5_AVAILABLE ? ("read_points ∘ write_points = id",
        begin
          path = joinpath(mktempdir(), "relation_points.h5")
          HDF5.h5open(f -> write_points(f, "p", b.points), path, "w")
          point_positions(HDF5.h5open(f -> read_points(f, "p"), path, "r"))
        end, point_positions(b.points)) :
       (:skip, nothing, nothing)),
      ("kernel composition is associative",
       field_data(convolve(b.sh, convolve(convolve(spectral_cutoff(m, b.T(3)),
                                                   spectral_band(m, b.T(1), b.T(4))),
                                          spectral_cutoff(m, b.T(2))))),
       field_data(convolve(b.sh, convolve(spectral_cutoff(m, b.T(3)),
                                          convolve(spectral_band(m, b.T(1), b.T(4)),
                                                   spectral_cutoff(m, b.T(2))))))),
      ("materialize agrees with compressed",
       field_data(convolve(b.sh, spectral_cutoff(m, b.T(3)))),
       field_data(convolve(b.sh, materialize_kernel(spectral_cutoff(m, b.T(3)))))),
    )

    # Coverage is recorded from the checks this lane ACTUALLY EVALUATES, matched to the table by name.
    # Recording it from the table itself credited three relations nobody ran — the very defect this
    # file's header says it exists to remove, moved up one level from the ledger to the lane.
    evaluated = Set(name for (name, _, _) in checks)
    for relation in RELATIONS
      relation.name in evaluated || continue
      for operation in relation.ops
        record_coverage!(operation, relation.kind)
      end
    end
    unevaluated = [r.name for r in RELATIONS if !(r.name in evaluated)]
    isempty(unevaluated) || config === first(configs) &&
      println("\n  DECLARED BUT NOT EVALUATED — ", length(unevaluated), " relations credit no coverage:\n",
              "      ", join(unevaluated, "; "))
    for check in checks
      name, got, want = check[1], check[2], check[3]
      # A relation whose expected value is EXACTLY ZERO may carry its own scale, because there is no
      # relative one to derive: `_scale` falls back to the larger of the two sides, and for these both
      # sides ARE the residual, so the tolerance collapsed to `_tolerance(T) * eps(Float32)` — about
      # 1e-18 on Float64 against a true roundoff residual of ~1e-13. Every such relation failed in every
      # configuration, 132 cells a run, and none of them was a defect. The scale supplied is the
      # magnitude of the same operation on data where it does NOT vanish.
      scale = length(check) >= 4 ? check[4] : nothing
      name === :skip && continue          # a dependency-gated relation: unevaluated, not passing
      cells += 1
      push!(seen, name)
      ok = relation_holds(name, got, want, rtol, b.T, scale)
      ok isa Symbol && (Base.push!(failures, "$(name) [$(config.name)] THREW $(ok)"); continue)
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
# A third-order section, built once per use. Decision 56 keeps STORAGE working above the ceiling — it is
# the fiber-assembly operations that refuse — so constructing this must itself succeed.
_third_order(b) = TensorFieldPhysical{3}(zeros(b.T, size(field_data(b.s))..., 3, 3, 3),
                                         field_grid(b.s), field_layout(b.s))


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

    for (kind, operations) in ((:representation, (:add!, :multiply!, :sym, :transpose, :integral, :mean, :inner)),
                               # `:invariance` is recorded where the check RUNS, below, not here: at
                               # `-t1` the lane reports NOT RUN and would otherwise still credit these.

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
      representations_agree(physical_result, spectral_result, rtol) === true ||
        record!(:representation, "$(name) disagrees between representations [$(config.name)]")
    end

    # ── thread-count invariance ─────────────────────────────────────────────────────────────────
    # The CPU paths are bitwise thread-count-invariant by contract, so this is `==`, not a tolerance.
    #
    # THE CUTOFF HAS TO COME DOWN FIRST. `_use_threads` returns false when the element count is below
    # `threading_cutoff` BEFORE it consults the `with_threading` override, and the largest fixture here
    # is 8·8·8·9 = 4608 elements against a default cutoff of 16384. Without this the `enabled = true`
    # and `enabled = false` runs both take the serial branch and the lane compares a path against
    # itself — decision 47's vacuous threading assertion, reproduced.
    # AND THE PROCESS MUST HAVE MORE THAN ONE THREAD. Lowering the cutoff makes `_use_threads` return
    # the override, but the threaded path then partitions by `Threads.nthreads()` — at `-t1` that is a
    # single slab running the identical body, so the comparison is still a path against itself. Fixing
    # only the cutoff left decision 47's vacuity in place for the suite's own documented invocation,
    # which passes no `-t`. Reported as NOT RUN rather than passed quietly.
    threads_available = Threads.nthreads() > 1
    previous_cutoff = threading_cutoff()
    set_threading_cutoff!(1)
    for (name, run) in
        (("add!", () -> field_data(add!(similar_field(b.u, Val(1)), b.u, b.v))),
         ("mul!", () -> field_data(mul!(similar_field(b.u, Val(1)), b.A, b.u))),
         ("sym!", () -> field_data(sym!(similar_field(b.A, Val(2)), b.A))),
         ("map!", () -> field_data(map!(x -> 2x, similar_field(b.s, Val(0)), b.s))),
         ("inner", () -> inner(b.u, b.v)),
         ("l2norm", () -> l2norm(b.u)),
         ("helmholtz_projection!", () -> field_data(helmholtz_projection!(similar_field(b.uh, Val(1)), b.uh, m))))
      if !threads_available
        config === first(configs) && name == "add!" &&
          println("      NOT RUN — thread invariance needs a process with more than one thread; at ",
                  "`-t1` the threaded path is a single slab and compares against itself. ",
                  "Run with JULIA_NUM_THREADS>1 to cross this axis.")
        continue
      end
      count!(:invariance)
      record_coverage!(Symbol(name), :invariance)
      serial = with_threading(run; enabled = false)
      threaded = with_threading(run; enabled = true)
      results_identical(serial, threaded) ||
        record!(:invariance, "$(name) is not bitwise thread-invariant [$(config.name)]")
    end

    set_threading_cutoff!(previous_cutoff)

    # ── allocation ──────────────────────────────────────────────────────────────────────────────
    # Invariant 13, measured on the CPU where a materialized array's bytes are actually counted.
    smallest_field = sizeof(eltype(field_data(b.s))) * length(field_data(b.s))
    allocation_bound = max(512, smallest_field ÷ 4)
    # The kernel is built ONCE, outside the measurement: constructing it inside the measured call
    # charged kernel construction to `convolve!`.
    allocation_kernel = spectral_cutoff(m, b.T(3))
    u, v, A, uh, vh, half = b.u, b.v, b.A, b.uh, b.vh, b.T(1) / 2
    # FRESH destinations. Measuring `add!(u, u, v)` in place mutated the workbench that the ordering
    # and rejection blocks below read, so those checks ran on data the seed does not name — the same
    # shared-fixture poisoning the invocation lane's per-cell `_refresh` exists to prevent.
    scratch_u, scratch_v = similar_field(u, Val(1)), similar_field(v, Val(1))
    copyto!(field_data(scratch_u), field_data(u)); copyto!(field_data(scratch_v), field_data(v))
    # MEASURED ON THE SERIAL ROUTE, because that is the route invariant 13 constrains. The invariant is
    # about FIELD-SIZED scratch — a per-call device temporary that escapes the GC and grows the pool
    # every step. The threaded route additionally spawns tasks, and that costs a small CONSTANT per
    # call: measured here at 3488 bytes for `add!`, identical whatever the field size, against 0 on the
    # serial route. Running this block under the configuration's own threading setting therefore
    # reported every in-place operation as allocating, in every threaded configuration — 336 cells a
    # run, none of them scratch, all of them the task objects. The gate's own audit measures serially
    # for the same reason.
    allocation_entry_cutoff = threading_cutoff()
    set_threading_cutoff!(typemax(Int))
    measurements =
        (("add!",                  single_allocated(add!, scratch_u, scratch_u, v)),
         ("combine!",              single_allocated(combine!, scratch_u, half, scratch_u, half, v)),
         ("mul!",                  single_allocated(mul!, scratch_v, A, u)),
         ("laplacian!",            single_allocated(laplacian!, similar_field(uh, Val(1)), uh, m)),
         ("curl!",                 single_allocated(curl!, similar_field(uh, Val(1)), uh, m)),
         ("helmholtz_projection!", single_allocated(helmholtz_projection!, similar_field(uh, Val(1)), uh, m)),
         ("convolve!",             single_allocated(convolve!, similar_field(uh, Val(1)), uh, allocation_kernel)),
         ("inner",                 single_allocated(inner, u, v)))
    set_threading_cutoff!(allocation_entry_cutoff)
    for (name, bytes) in measurements
      count!(:allocation)
      # Scaled to the SMALLEST field in play, not a fixed 4096. A scalar Float32 field on 8³ is 2048 B
      # and a scalar spectral Float64 field on (7,5,3) is 960 B, so a flat 4 KB bound let a full
      # per-call scratch field — the exact defect invariant 13 exists for — pass on every small grid.
      bytes < allocation_bound ||
        record!(:allocation, "$(name) allocated $(bytes) bytes on a preallocated call, against a " *
                             "smallest field of $(smallest_field) bytes [$(config.name)]")
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
          l2norm(convolve(b.sh, spectral_cutoff(m, b.T(3)))) <= l2norm(b.sh) * (1 + 1e-8)))
      count!(:inequality)
      holds || record!(:inequality, "$(name) is violated [$(config.name)]")
    end

    # ── domain rejection: the call must NOT succeed ─────────────────────────────────────────────
    # Numeric arguments outside their documented domain, which the mismatch lane does not reach: it
    # varies the OBJECTS, and these are scalars.
    for (name, call) in
        (("lpnorm with p < 1", () -> lpnorm(b.u, 0.5)),
         ("lpnorm with a negative p", () -> lpnorm(b.u, -2)),
         ("spectral_band with lo > hi", () -> spectral_band(m, b.T(3), b.T(1))),
         ("spectral_band with a negative edge", () -> spectral_band(m, -b.T(1), b.T(3))),
         ("spectral_cutoff with a NaN edge", () -> spectral_cutoff(m, b.T(NaN))),
         ("NUFFT with a non-positive tolerance", () -> NUFFT(z; tol = zero(b.T))),

         ("NUFFT with a negative tolerance", () -> NUFFT(z; tol = -b.T(1))),
         # CROSSED OVER THE AXIS. Both fixtures corrupted axis 1 only, so per-axis validation that
         # checked the first extent and skipped the rest — an ordinary loop-bound slip — would have
         # accepted a zero or NaN extent on axes 2 and 3 with nothing here to notice.
         ("a grid with a zero extent on axis 1", () -> Grid3D((8, 8, 8), (zero(b.T), one(b.T), one(b.T)))),
         ("a grid with a zero extent on axis 2", () -> Grid3D((8, 8, 8), (one(b.T), zero(b.T), one(b.T)))),
         ("a grid with a zero extent on axis 3", () -> Grid3D((8, 8, 8), (one(b.T), one(b.T), zero(b.T)))),
         ("a grid with a NaN extent on axis 1", () -> Grid3D((8, 8, 8), (b.T(NaN), one(b.T), one(b.T)))),
         ("a grid with a NaN extent on axis 2", () -> Grid3D((8, 8, 8), (one(b.T), b.T(NaN), one(b.T)))),
         ("a grid with a NaN extent on axis 3", () -> Grid3D((8, 8, 8), (one(b.T), one(b.T), b.T(NaN)))),
         ("set_threading_cutoff! below one", () -> set_threading_cutoff!(0)),
         # DECISION 49: `var`/`std` are scalar-only and must say so for a vector or tensor section,
         # pointing at `cov`. The method EXISTS for R > 0 and raises, so `applicable` says yes and the
         # engine builds the call — which makes this reachable, and it was simply never asked.
         ("var of a vector section", () -> var(b.u)),
         ("std of a tensor section", () -> std(b.A)),
         # DECISION 45: the four-argument `Grid3D` rejects a spacing that contradicts
         # `domain_size ./ grid_size`. The survey builds that constructor only on its VALID path, so the
         # rejection this decision exists for was never exercised here.
         ("a grid whose spacing contradicts its domain",
          () -> Grid3D((8, 8, 8), (b.T(2π), b.T(2π), b.T(2π)),
                       (b.T(1), b.T(2π) / 8, b.T(2π) / 8), (zero(b.T), zero(b.T), zero(b.T)))),
         ("a section over borrowed storage",
          () -> ScalarFieldPhysical(view(rand(b.T, config.grid.grid_size .+ 1...),
                                         1:config.grid.grid_size[1], 1:config.grid.grid_size[2],
                                         1:config.grid.grid_size[3]), config.grid, config.layout)))
      count!(:domain_rejection)
      # The exception TYPE, not merely that something was thrown. `catch; true` counts a `MethodError`
      # from a renamed keyword or a typo in the test as a correct refusal, so a deleted validation stays
      # green as long as the call fails for any other reason.
      outcome = try
        call()
        :accepted
      catch exception
        is_domain_refusal(exception) ? :rejected : nameof(typeof(exception))
      end
      outcome === :rejected ||
        record!(:domain_rejection, outcome === :accepted ? "$(name) was ACCEPTED [$(config.name)]" :
                "$(name) threw $(outcome), not a domain error [$(config.name)]")
    end

    # ── decision 56's ceiling: above R = 2, every entry point works or THROWS ────────────────────
    # A separate bar from the table above, deliberately. That one demands a DOMAIN error, because a bare
    # `MethodError` there would mean a renamed keyword or a typo in the test rather than a refusal. The
    # ceiling's contract is different: `sym`, `skew`, `dev` and `map` are enumerated for R ≤ 2 and simply
    # have no method above it, so `MethodError` IS the documented refusal and demanding an `ArgumentError`
    # would report correct behaviour as a defect. What must never happen is a RETURNED VALUE, since the
    # contract's whole point is that the ceiling never yields a wrong answer quietly. The pools stop at
    # R = 2, so nothing in the survey had ever built a third-order section.
    third = _third_order(b)
    for (name, call) in (("sym", () -> sym(third)), ("skew", () -> skew(third)),
                         ("dev", () -> dev(third)), ("map", () -> map(identity, third)),
                         ("mean under a fiber map", () -> mean(norm, third)))
      count!(:domain_rejection)
      returned = try (call(); true) catch; false end
      returned && record!(:domain_rejection,
                          "$(name) above the R < 3 ceiling RETURNED a value instead of throwing " *
                          "[$(config.name)]")
    end
  end

  total = 0
  println()
  for kind in (:representation, :invariance, :allocation, :inequality, :domain_rejection)
    n = get(counts, kind, 0)
    failures = get(results, kind, String[])
    total += length(failures)
    println("      ", rpad(String(kind), 18), lpad(n, 7), " cells   ",
            n == 0 ? "NOT RUN — no cell was constructed for this check" :
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
