# Derive the CHECK-TYPE axis by classifying the assertions people have already written.
#
#   julia --project=. test/exhaustive/classify_checks.jl
#
# The design's claim — no test a person would write is outside the product — is only verifiable if the
# check-type axis is derived rather than listed. The existing suite IS what people write, so the axis
# is obtained from it, and an assertion matching no class is a check type the design has not named.
#
# The classes below are patterns and the counts are therefore approximate; a `@test` may fit two
# classes and takes the first. THE COUNTS ARE NOT THE OUTPUT. The residue is: every class here after
# the first five was added because an assertion fell through, and the design's hand-written list had
# missed `result_type`, `inequality`, `static_absence`, `schema_presence` and `structural`.
#
# Run it after adding tests. A growing residue means the axis has a value the product does not cover.

# Classify every assertion in test/ by CHECK TYPE. The classes are patterns; what matters is the
# residue — an assertion matching none is a check type the design has not named.
const CLASSES = [
  (:allocation,      [r"@allocated", r"@alloc_below", r"alloc"]),
  (:type_stability,  [r"@inferred", r"@test_call", r"JET"]),
  (:element_traffic, [r"Traffic\(", r"audit\("]),
  (:absence,         [r"@test_throws\s+MethodError"]),
  # `DomainError` too, and `BoundsError` kept: the suite's two other rejection filters
  # (properties.jl, pools.jl) accept ArgumentError/DimensionMismatch/InexactError/DomainError, and this
  # one listed BoundsError instead of DomainError with no stated reason.
  (:domain_rejection,[r"@test_throws\s+(ArgumentError|DimensionMismatch|BoundsError|InexactError|DomainError)"]),
  (:completeness,    [r"isempty\(setdiff", r"isempty\(uncovered", r"isempty\(unclassified",
                      r"isempty\(phantoms", r"isempty\(missing", r"_method_count", r"module_method_count"]),
  (:metadata,        [r"field_grid\(", r"field_layout\(", r"field_tensor_order\(", r"eltype\(field_data"]),
  (:round_trip,      [r"round.?trip", r"to_physical\(to_spectral", r"to_spectral\(to_physical",
                      r"read_field", r"read_points"]),
  (:adjoint,         [r"adjoint", r"⟨", r"inner\(.*\).*≈.*inner\("]),
  (:identity,        [r"div.*curl", r"curl.*grad", r"sym.*skew", r"idempot", r"== *0\b", r"≈ *0\b"]),
  (:invariance,      [r"bitwise", r"threaded", r"with_threading", r"serial", r"aliased", r"alias"]),
  (:determinism,     [r"determinis", r"reproducib", r"seed"]),
  # SURFACED BY THE RESIDUE, not by the design's list:
  (:static_absence,  [r"!hasmethod", r"hasmethod\("]),      # absence proven statically, not by throwing
  # `haskey(` alone missed how the suite actually asserts a schema: it READS the attribute and compares
  # it (`attrs(g)["version"] == 1`), so every positive schema assertion in `hdf5.jl` was typed
  # `:correct` and the check read 0/4 while being thoroughly asserted (2026-08-17).
  (:schema_presence, [r"haskey\(", r"attrs\("]),            # a serialized attribute is present/absent
  (:structural,      [r"all\(iszero", r"any\(iszero", r"imag\.\(", r"all\(isreal", r"issymmetric"]),
  (:representation,  [r"\bsame\(", r"spectral.*physical|physical.*spectral"]),
  (:result_type,     [r"\bisa\b"]),                        # the operation returns the declared type
  # `[^=!<>]>[^=]` matches `->`, so every assertion containing a lambda — and every `where {T<:Real}` —
  # was filed as an inequality, shifting credit off `:correct` for both the report and the residue that
  # defines the axis. The arrow and the subtype operator are excluded explicitly.
  # Exclude the ARROW and the SUBTYPE operator, not the inequality. An earlier fix here removed `->`
  # and `<:` by forbidding `=` after the glyph — which also removed `<=` and `>=`, the two most common
  # inequality spellings in the suite, sending them through every class into "unclassified", which the
  # design reads as a check type nobody has ever written.
  (:inequality,      [r"(?<![-=!<>])<(?!:)", r"(?<![-=!<>])>", r"≤", r"≥", r"\bsign\b"]),  # sign, definiteness, bounds
  (:correct,         [r"≈", r"==", r"isapprox", r"\bapprox\("]),          # the catch-all, deliberately last
]

function classify()
  total = 0; counts = Dict{Symbol,Int}(); residue = String[]
  for file in sort(readdir("test"; join = true))
    endswith(file, ".jl") || continue
    for (n, line) in enumerate(eachline(file))
    occursin(r"@test\b|@test_throws|@inferred|@allocated", line) || continue
    total += 1
    matched = nothing
    for (class, patterns) in CLASSES
      any(p -> occursin(p, line), patterns) && (matched = class; break)
    end
    if matched === nothing
      push!(residue, "$(basename(file)):$n  $(strip(line)[1:min(end,72)])")
    else
      counts[matched] = get(counts, matched, 0) + 1
    end
  end
end
println("assertions classified: ", total)
for (k, v) in sort(collect(counts); by = x -> -x[2]); println("  ", rpad(k, 20), v); end
println("\nUNCLASSIFIED (each is a check type the design has not named): ", length(residue))
for r in residue[1:min(end, 25)]; println("  ", r); end
end
classify()
