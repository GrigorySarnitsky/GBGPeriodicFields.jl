# The exhaustive suite — the full Cartesian product, run occasionally rather than on every change.
#
#   julia --project=. test/exhaustive/runtests.jl
#
# It is NOT part of `Pkg.test()`, for the same reason the GPU suite and the benchmarks are not: the
# default suite is a gate that must stay fast, and this is a survey that must stay complete. The
# default suite runs ~6 minutes; this one has no such budget and should not be given one.
#
# HOW TO READ IT. This is a REPORT, not a gate that has been silenced. It runs blind to what the
# package has decided, and prints everything that does not work. Where a failure corresponds to a
# recorded decision or a documented contract, the citation is printed BESIDE it — as an explanation of
# a known gap, never as a reason to call it green. A failure with no citation is a new finding.
#
# Its purpose is to be the place where combinations are enumerated rather than chosen, so that a defect
# is found by the product rather than by someone remembering to look.

using GBGPeriodicFields
using Statistics

include("aliasing.jl")
include("references.jl")
include("pools.jl")
include("ledger.jl")

# Citations, applied to output only. Nothing here suppresses, filters or greens a failure: a cited
# entry is still reported as not working. The citation answers "is this known?", not "is this fine?".
# Citations, applied to output only. Nothing here suppresses, filters or greens a failure: a cited
# entry is still reported as not working. The citation answers "is this known?", not "is this fine?".
#
# The nine entries this table carried for the fused-pass corruption are GONE, because decision 59 made
# the input unconstructible rather than the arithmetic safe. A citation for a class that can no longer
# be reached is not documentation, it is residue.
const CITATIONS = Dict{Symbol, String}(
  :mul! => "BY CONTRACT — mul! follows the LinearAlgebra convention that the destination must not " *
           "alias an input (invariant 9)",
)

const PHYSICAL = false
const SPECTRAL = true

# The operation table is built per configuration, because the multipliers, the helper operands and the
# kernel all have to live on the same grid, layout and element type as the pool.
function operations_for(c::Config)
  T = c.eltype
  sspec = ScalarFieldSpectral(zeros(Complex{T}, xshape(c, 0, SPECTRAL)), c.grid, c.layout)
  m = FieldSpectralMultipliers(sspec)
  v = VectorFieldPhysical(rand(T, xshape(c, 1, PHYSICAL)...), c.grid, c.layout)
  A = TensorFieldPhysical{2}(rand(T, xshape(c, 2, PHYSICAL)...), c.grid, c.layout)
  kernel = translation_kernel(sspec, m, ntuple(d -> T(0.5) * c.grid.grid_spacing[d], 3))
  α, β = T(0.3), T(0.7)
  return [
    (:add!,                  [1, 1, 1], PHYSICAL, (d, a, b) -> add!(d, a, b)),
    (:subtract!,             [1, 1, 1], PHYSICAL, (d, a, b) -> subtract!(d, a, b)),
    (:combine!,              [1, 1, 1], PHYSICAL, (d, a, b) -> combine!(d, α, a, β, b)),
    (:multiply!,             [1, 1],    PHYSICAL, (d, a) -> multiply!(d, a, T(2))),
    (:divide!,               [1, 1],    PHYSICAL, (d, a) -> divide!(d, a, T(2))),
    (:cross!,                [1, 1],    PHYSICAL, (d, a) -> cross!(d, a, v)),
    (:dot!,                  [0, 1],    PHYSICAL, (d, a) -> dot!(d, a, v)),
    (:mul!,                  [1, 1],    PHYSICAL, (d, a) -> mul!(d, A, a)),
    (:sym!,                  [2, 2],    PHYSICAL, (d, a) -> sym!(d, a)),
    (:skew!,                 [2, 2],    PHYSICAL, (d, a) -> skew!(d, a)),
    (:dev!,                  [2, 2],    PHYSICAL, (d, a) -> dev!(d, a)),
    (:transpose!,            [2, 2],    PHYSICAL, (d, a) -> transpose!(d, a)),
    (:tr!,                   [0, 2],    PHYSICAL, (d, a) -> tr!(d, a)),
    (:det!,                  [0, 2],    PHYSICAL, (d, a) -> det!(d, a)),
    (:norm!,                 [0, 1],    PHYSICAL, (d, a) -> norm!(d, a)),
    (:map!,                  [1, 1],    PHYSICAL, (d, a) -> map!(x -> 2x, d, a)),
    # The α/β accumulate arities reach a different branch of the same passes (the destination is READ
    # as well as written when β ≠ 0). Derived, not guessed: only these operations have such a form —
    # `dot!` and `cross!` do not, and asserting otherwise is what produced this lane's first false
    # finding, correctly surfaced as UNEXPLAINED because no decision could explain a MethodError.
    (Symbol("mul!·αβ"),      [1, 1],    PHYSICAL, (d, a) -> mul!(d, A, a, α, β)),
    (Symbol("map!·αβ"),      [1, 1],    PHYSICAL, (d, a) -> map!(x -> 2x, d, a, α, β)),
    (:laplacian!,            [0, 0],    SPECTRAL, (d, a) -> laplacian!(d, a, m)),
    (:inverse_laplacian!,    [0, 0],    SPECTRAL, (d, a) -> inverse_laplacian!(d, a, m)),
    (:gradient!,             [1, 0],    SPECTRAL, (d, a) -> gradient!(d, a, m)),
    (:divergence!,           [0, 1],    SPECTRAL, (d, a) -> divergence!(d, a, m)),
    (:curl!,                 [1, 1],    SPECTRAL, (d, a) -> curl!(d, a, m)),
    (:symmetric_gradient!,   [2, 1],    SPECTRAL, (d, a) -> symmetric_gradient!(d, a, m)),
    (:helmholtz_projection!, [1, 1],    SPECTRAL, (d, a) -> helmholtz_projection!(d, a, m)),
    (:convolve!,             [1, 1],    SPECTRAL, (d, a) -> convolve!(d, a, kernel)),
    (Symbol("convolve!·αβ"), [1, 1],    SPECTRAL, (d, a) -> convolve!(d, a, kernel, α, β)),
    (:exponential_convolve!, [0, 0],    SPECTRAL, (d, a) -> exponential_convolve!(d, a, m, -T(1) / 10)),
    (Symbol("exponential_convolve!·αβ"), [0, 0], SPECTRAL,
       (d, a) -> exponential_convolve!(d, a, m, -T(1) / 10, α, β)),
    # divergence!'s α/β form is the KERNEL-COMPOSED arity of decision 32, so it takes a kernel too.
    (Symbol("divergence!∘kernel·αβ"), [0, 1], SPECTRAL, (d, a) -> divergence!(d, a, m, kernel, α, β)),
    (Symbol("helmholtz_projection!∘kernel·αβ"), [1, 1], SPECTRAL,
       (d, a) -> helmholtz_projection!(d, a, m, kernel, α, β)),
  ]
end


# The design requires a reference to be CROSS-VALIDATED before it is used as an oracle, and this is
# where that happens. A reference that shares a misconception with the implementation makes every cell
# using it pass while both are wrong — the self-referential oracle of decision 52, which this suite
# already rebuilt once by comparing an aliased call against an unaliased one.
#
# So the references are checked against the package on ordinary input first. Agreement is meaningful
# because they share no code: the wavenumbers here are rebuilt from the grid rather than taken from
# `FieldSpectralMultipliers`, so a convention error in the package cannot hide by being copied.
function run_reference_lane()
  println("═"^100)
  println("LANE: reference cross-validation — the oracle must be independently right before it is used")
  println("═"^100)
  disagreements = String[]
  checked = 0
  for c in configurations()
    T = c.eltype
    SH(R) = xshape(c, R, true)
    s = ScalarFieldSpectral(randn(Complex{T}, SH(0)...), c.grid, c.layout)
    u = VectorFieldSpectral(randn(Complex{T}, SH(1)...), c.grid, c.layout)
    m = FieldSpectralMultipliers(s)
    rtol = T === Float32 ? 1.0f-3 : 1e-9
    for (name, got, want) in (
        ("gradient",             field_data(gradient(s, m)),             ref_gradient(field_data(s), c.grid, c.layout)),
        ("divergence",           field_data(divergence(u, m)),           ref_divergence(field_data(u), c.grid, c.layout)),
        ("curl",                 field_data(curl(u, m)),                 ref_curl(field_data(u), c.grid, c.layout)),
        ("laplacian",            field_data(laplacian(s, m)),            ref_laplacian(field_data(s), c.grid, c.layout)),
        ("inverse_laplacian",    field_data(inverse_laplacian(s, m)),    ref_inverse_laplacian(field_data(s), c.grid, c.layout)),
        ("symmetric_gradient",   field_data(symmetric_gradient(u, m)),   ref_symmetric_gradient(field_data(u), c.grid, c.layout)),
        ("helmholtz_projection", field_data(helmholtz_projection(u, m)), ref_helmholtz(field_data(u), c.grid, c.layout)))
      checked += 1
      isapprox(Array(got), Array(want); rtol = rtol) ||
        push!(disagreements, "$name [$(c.name)]")
    end
  end
  if isempty(disagreements)
    println("\n  ", checked, " reference/implementation pairs agree across ", length(configurations()), " configurations")
  else
    println("\n  THE ORACLE AND THE PACKAGE DISAGREE — one of them is wrong, and no cell using this")
    println("  reference means anything until it is resolved:")
    for d in disagreements; println("      ", d); end
  end
  return length(disagreements)
end


function run_aliasing_lane()
  configs = configurations()
  println("═"^100)
  println("LANE: storage aliasing — every in-place operation × every storage relation × ",
          length(configs), " configurations")
  println("      axes crossed: element type, grid shape/parity/anisotropy, spectral fold, thread count,")
  println("                    storage kind (Array/SubArray), aliasing relation, tensor order, representation")
  println("═"^100)

  # (operation, assignment) => the configurations in which it disagrees
  failures = Dict{Tuple{Symbol, String}, Vector{String}}()
  order_changing = Set{Symbol}()
  cases = 0
  for c in configs
    previous = threading_cutoff()
    set_threading_cutoff!(c.threaded ? 1 : typemax(Int))
    for (name, orders, representation, call) in operations_for(c)
      found = aliasing_failures(c, orders, representation, call)
      cases += 3 ^ length(orders)
      isempty(found) && length(unique(orders)) > 1 && push!(order_changing, name)
      for assignment in found
        push!(get!(failures, (name, assignment), String[]), c.name)
      end
    end
    set_threading_cutoff!(previous)
  end

  # The other half of the axis: the borrowed-storage constructions that closed the class must STAY
  # closed. A refusal that stops refusing is a silent reopening, so it is checked per configuration and
  # per tensor order rather than assumed from the constructor's source.
  reopened = String[]
  for c in configs, R in (0, 1, 2), cplx in (false, true)
    for name in refused_constructions(c, R, cplx)
      push!(reopened, "$(name) at R=$R $(cplx ? "spectral" : "physical") [$(c.name)]")
    end
    cases += 3
  end

  affected = sort(unique(first(k) for k in keys(failures)); by = string)
  unexplained = String[]
  for name in affected
    entries = sort([(a, cs) for ((n, a), cs) in failures if n == name]; by = first)
    println("\n  ", name)
    for (assignment, in_configs) in entries
      println("      ", rpad(assignment, 26),
              length(in_configs) == length(configs) ? "in ALL $(length(configs)) configurations" :
                                                     "in $(length(in_configs))/$(length(configs)): " * join(in_configs, ", "))
    end
    # A row's name may carry arity qualifiers — `helmholtz_projection!∘kernel·αβ` — so normalize to the
    # operation itself before looking up a citation, or the same known defect reads as a new finding
    # under every qualified spelling.
    base = Symbol(first(split(String(name), ('∘', '·'))))
    citation = get(CITATIONS, base, nothing)
    if citation === nothing
      println("      NO CITATION — this is a new finding")
      push!(unexplained, String(name))
    else
      println("      cited: ", citation)
    end
  end

  if !isempty(reopened)
    println("\n  BORROWED STORAGE ACCEPTED — decision 59's refusal has reopened:")
    for r in reopened; println("      ", r); end
    push!(unexplained, "borrowed-storage refusal")
  end

  println("\n", "─"^100)
  println("SUMMARY  ", cases, " cases over ", length(configs), " configurations")
  println("         ", length(affected), " operations have assignments that change the answer")
  isempty(unexplained) || println("         ", length(unexplained), " UNEXPLAINED: ", join(unexplained, ", "))
  isempty(order_changing) ||
    println("         NOT APPLICABLE to ", length(order_changing), " order-changing operations (",
            join(sort(string.(collect(order_changing))), ", "), "):\n",
            "         sections of different tensor order cannot share storage through the public API —\n",
            "         a component is obtained by contraction (`dot(u, e_x)`), which allocates. Not a gap.")
  return length(affected), length(unexplained), cases
end

disagreeing = run_reference_lane()
println()
affected, unexplained, cases = run_aliasing_lane()
println()
mismatch_findings, mismatch_cells = run_mismatch_lane()
println()
ledger_gaps, ledger_violations, ledger_cells = run_ledger_lane()
println()

println("═"^100)
println("REPORT — ", cases + mismatch_cells + ledger_cells, " cells over four lanes")
println("═"^100)
println("  reference cross-validation   ", disagreeing == 0 ? "oracle agrees with the package" :
                                           "$(disagreeing) DISAGREEMENTS — no cell using it means anything")
println("  storage aliasing             ", affected, " operations with a disagreeing assignment, ",
        unexplained, " uncited")
println("  context mismatch             ", mismatch_findings, " findings over ", mismatch_cells, " cells")
println("  applicability ledger         ", ledger_gaps, " applicable-but-unasserted cells, ",
        ledger_violations, " guard violations")
println()
println("  A gap in the ledger is a COVERAGE report, not a failure: it says a question the design")
println("  admits has not been asked of that operation. The exit status is driven by the lanes that")
println("  assert behaviour, so a survey number can grow without turning the report red.")

exit(disagreeing > 0 || unexplained > 0 || mismatch_findings > 0 || ledger_violations > 0 ? 2 :
     (affected > 0 ? 1 : 0))
