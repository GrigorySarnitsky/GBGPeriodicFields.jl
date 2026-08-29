# Recorded reasons a `(operation, method)` cell cannot carry a value-lane row.
#
# THIS FILE IS THE ESCAPE HATCH, so it is built to be hard to abuse. A reason closes exactly ONE
# method, named by its SIGNATURE, and the ledger prints reason-closed cells separately from
# row-covered ones — "covered by a sibling builder" must never become a way to make anything green.
# A reason naming a signature no method has is reported STALE rather than silently ignored, so
# deleting the method it excused surfaces the excuse instead of leaving it to rot.
#
# KEYED BY SIGNATURE, NOT BY DEFINITION SITE, and both halves of that were learned the hard way.
# Site keying let one entry silently close FOUR codegen methods sharing an `@eval` line — the escape
# widening itself, caught by probe 4 — and it was invalidated by any edit ABOVE the method, which the
# stale check then reported as a missing method when only the line number had moved. A signature is
# stable under edits and names exactly one method, so a reason can neither drift nor over-close.
#
# The legitimate classes, and nothing else belongs here:
#
#   :unreachable  — the method cannot be called with any argument the package admits, so no row exists
#                   that could drive it (a fallback whose sole purpose is to throw a better error).
#
# A REASON IS NOT A DISMISSAL, and every entry here has to show it. A cell closed here is one no VALUE
# oracle can drive, because the method returns no value to compare — but its behaviour, which is a
# refusal, is asserted somewhere, and each reason CITES the assertion by file and line. If a reason
# cannot name one, the honest options are to write that assertion or to leave the cell uncovered; what
# it must not become is a place where a method quietly stops being tested.
#   :not_a_value  — the method returns no value an oracle can compare: a setter, a printer, a
#                   constructor of an opaque handle.
#   :device_only  — the method dispatches on a device backend and a CPU survey cannot reach it. The
#                   GPU parity suite is where it is checked, and that is a different instrument.

const LEDGER_REASONS = Dict{String, Tuple{Symbol, String}}(
  # Error fallbacks. Both exist to REFUSE a call and say why, so there is no value for an oracle to
  # compare; the refusal itself is asserted by the survey's domain-rejection lane, not here.
  "Tuple{typeof(extrema), AbstractFiberSection}" => (:not_a_value,
    "`extrema` on a non-scalar section throws: an order statistic above R = 0 is ill-posed until a fiber map names what is ordered — refusal asserted at test/reductions.jl:664-665"),
  "Tuple{typeof(var), AbstractFiberSection}" => (:not_a_value,
    "`var` on a non-scalar section throws: the fiber-preserving variance is basis-dependent and the package declines it — refusal asserted at test/reductions.jl:658,668"),
  # The two ambiguity resolvers of the scalar-by-scalar product, one per layer. A destination whose
  # order matches reaches the more specific method; one whose order does not is refused — which for
  # the point layer became true only on 2026-08-29, when writing a row to reach this very cell showed
  # it accepting what its field twin had always refused.
  "Tuple{typeof(multiply!), AbstractFieldPhysical, ScalarFieldPhysical, ScalarFieldPhysical}" => (:unreachable,
    "exists to resolve dispatch ambiguity; a matching destination reaches the more specific method and a mismatched one is refused — refusal asserted at test/regressions/pointvalues-scalar-action-wrong-order-destination.jl:26"),
  "Tuple{typeof(multiply!), AbstractPointValues, ScalarPointValues, ScalarPointValues}" => (:unreachable,
    "the point twin of the above, unreachable for the same reason now that the destination's tensor order is checked — refusal asserted at test/regressions/pointvalues-scalar-action-wrong-order-destination.jl:18"),
)


"""
    ledger_reason(cell) -> Union{Nothing, String}

The recorded reason this method cannot have a value row, or `nothing` if none is recorded — in which
case an uncovered method is a finding.
"""
function ledger_reason(cell)
  entry = get(LEDGER_REASONS, string(cell.method.sig), nothing)
  entry === nothing && return nothing
  return string(entry[1], ": ", entry[2])
end


"""
    ledger_stale_reasons(cells) -> Vector{String}

Recorded reasons whose signature no method carries. A stale reason is reported rather than ignored:
the excuse outliving the method it excused is exactly how an escape hatch becomes permanent.
"""
function ledger_stale_reasons(cells)
  live = Set(string(cell.method.sig) for cell in cells)
  return sort([first(signature, 70) for signature in keys(LEDGER_REASONS) if !(signature in live)])
end


"""
    ledger_miscounted_reasons(cells) -> Vector{String}

Reasons that would close more than one method. A signature identifies exactly one method, so this is
empty by construction — it is kept because the ledger's probe asserts it, and an assertion that can
only pass by construction is the cheapest kind to keep true.
"""
function ledger_miscounted_reasons(cells)
  seen = Dict{String, Int}()
  for cell in cells
    signature = string(cell.method.sig)
    haskey(LEDGER_REASONS, signature) && (seen[signature] = get(seen, signature, 0) + 1)
  end
  return sort([string(first(k, 60), " matches ", v, " methods") for (k, v) in seen if v != 1])
end
