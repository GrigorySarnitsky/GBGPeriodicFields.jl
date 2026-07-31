# The VALUE lane: is the computed result correct?
#
# This is the lane the suite was missing. The universal checks in `checks.jl` verify PROPERTIES — that
# a call corrupts no input, returns something finite, keeps its metadata, reproduces, and infers a
# concrete type — and a wrong answer passes every one of them. A `gradient` returning 2∇f instead of
# ∇f is finite, reproducible, metadata-preserving and type-stable. Before this lane the only operations
# whose VALUE was checked here were the seven spectral operators, 168 cells out of 85008.
#
# Each reference in `references.jl` is written from the operation's DOCUMENTED definition — the display
# formula in its own docstring — and from raw arrays, sharing no code with the implementation. That
# direction matters: an oracle copied off the code checks that the code equals itself, while one
# written from the stated contract checks that the code means what the documentation claims, so a
# disagreement is a finding either way round.

using GBGPeriodicFields
using Statistics
using LinearAlgebra


# A tolerance that tracks the element type and the length of the reduction. The references sum in a
# different order from the package (a plain loop against a pairwise-blocked or fused pass), so exact
# equality is not the property — agreement to the arithmetic's own precision is.
_value_tolerance(T) = T === Float32 ? 1.0f-4 : 1e-10

_as_array(x) =
  x isa GBGI.FiberSections.AbstractFiberSection ? Array(field_data(x)) :
  x isa Number                                  ? [x] :
  x isa Tuple                                   ? collect(Float64, x) :
  x isa AbstractArray                           ? Array(x) : [x]


"""
    run_value_lane(configs) -> (disagreements, cells)

Compare every covered operation's computed result against an independent reference, over every
configuration.
"""
function run_value_lane(configs)
  println("═"^100)
  println("LANE: value correctness — the computed result against an INDEPENDENT reference")
  println("      each reference is written from the operation's documented definition, over raw")
  println("      arrays, sharing no code with the implementation")
  println("═"^100)

  disagreements = String[]
  cells = 0
  covered = Set{Symbol}()

  for config in configs
    T, grid, layout = config.eltype, config.grid, config.layout
    rtol = _value_tolerance(T)
    P(R) = (grid.grid_size..., ntuple(_ -> 3, R)...)
    s  = ScalarFieldPhysical(rand(T, P(0)...), grid, layout)
    s2 = ScalarFieldPhysical(rand(T, P(0)...), grid, layout)
    u  = VectorFieldPhysical(rand(T, P(1)...), grid, layout)
    v  = VectorFieldPhysical(rand(T, P(1)...), grid, layout)
    A  = TensorFieldPhysical{2}(rand(T, P(2)...), grid, layout)
    B  = TensorFieldPhysical{2}(rand(T, P(2)...), grid, layout)
    α, β = T(3) / 10, T(7) / 10
    ds, du, dA = field_data(s), field_data(u), field_data(A)

    # (name, what the package computes, what the definition says it should be)
    comparisons = (
      # ── the vertical (fiberwise) algebra ──────────────────────────────────────────────────────
      (:+,          u + v,                    ref_add(du, field_data(v))),
      (:-,          u - v,                    ref_subtract(du, field_data(v))),
      (:combine!,   combine!(similar_field(u, Val(1)), α, u, β, v),
                                              ref_combine(α, du, β, field_data(v))),
      (:add!,       add!(similar_field(u, Val(1)), u, v), ref_add(du, field_data(v))),
      (:subtract!,  subtract!(similar_field(u, Val(1)), u, v), ref_subtract(du, field_data(v))),
      (:multiply!,  multiply!(similar_field(u, Val(1)), u, α), ref_scale(du, α)),
      (:divide!,    divide!(similar_field(u, Val(1)), u, α), ref_divide(du, α)),
      (:cross,      cross(u, v),              ref_cross(du, field_data(v))),
      (:dot,        dot(u, v),                ref_dot(du, field_data(v))),
      (:norm,       norm(u),                  ref_norm(du)),
      (:transpose,  transpose(A),             ref_transpose(dA)),
      (:sym,        sym(A),                   ref_sym(dA)),
      (:skew,       skew(A),                  ref_skew(dA)),
      (:tr,         tr(A),                    ref_trace(dA)),
      (:dev,        dev(A),                   ref_dev(dA)),
      (:det,        det(A),                   ref_det(dA)),
      (:mul!,       mul!(similar_field(u, Val(1)), A, u), ref_matvec(dA, du)),
      (:map,        map(x -> 2x, s),          ref_scale(ds, T(2))),
      # ── the L²/measure reductions ─────────────────────────────────────────────────────────────
      (:mean,       mean(s),                  only(ref_mean(ds, 0))),
      (:mean,       collect(mean(u)),         ref_mean(du, 1)),
      (:integral,   integral(s),              only(ref_integral(ds, 0, grid))),
      (:integral,   collect(integral(u)),     ref_integral(du, 1, grid)),
      (:inner,      inner(s, s2),             ref_inner(ds, field_data(s2), 0)),
      (:inner,      inner(u, v),              ref_inner(du, field_data(v), 1)),
      (:inner,      inner(A, B),              ref_inner(dA, field_data(B), 2)),
      (:l2norm,     l2norm(u),                ref_l2norm(du, 1)),
      (:l2norm,     l2norm(A),                ref_l2norm(dA, 2)),
      (:lpnorm,     lpnorm(u, 1),             ref_lpnorm(du, 1, 1)),
      (:lpnorm,     lpnorm(u, 2),             ref_lpnorm(du, 2, 1)),
      (:lpnorm,     lpnorm(u, 3),             ref_lpnorm(du, 3, 1)),
      (:lpnorm,     lpnorm(u, Inf),           ref_lpnorm(du, Inf, 1)),
      (:lpnorm,     lpnorm(A, 2),             ref_lpnorm(dA, 2, 2)),
      (:var,        var(s),                   ref_var(ds)),
      (:std,        std(s),                   ref_std(ds)),
      (:cov,        Array(cov(u)),            ref_cov(du)),
      (:maximum,    maximum(s),               maximum(ds)),
      (:minimum,    minimum(s),               minimum(ds)),
      (:extrema,    collect(extrema(s)),      [minimum(ds), maximum(ds)]),
    )

    for (name, got, want) in comparisons
      cells += 1
      push!(covered, name)
      isapprox(_as_array(got), _as_array(want); rtol = rtol) && continue
      Base.push!(disagreements, "$(name) [$(config.name)]")
    end
  end

  println("\n  ", cells, " value comparisons over ", length(configs), " configurations · ",
          length(covered), " operations have an independent oracle here")
  if isempty(disagreements)
    println("  every computed result matches its independent reference")
  else
    println("\n  THE COMPUTED RESULT DISAGREES WITH THE DEFINITION — ", length(disagreements), " cells.")
    println("  One of the two is wrong: the implementation, or the docstring the reference was")
    println("  written from. Both are findings.")
    for d in unique(disagreements); println("      ", d); end
  end
  return (length(disagreements), cells, length(covered))
end
