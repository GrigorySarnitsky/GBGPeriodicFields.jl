# Recorded reasons a `(operation, method)` cell cannot carry a value-lane row.
#
# THIS FILE IS THE ESCAPE HATCH, so it is built to be hard to abuse. A reason closes ONE method, named
# by its definition site, and the ledger prints reason-closed cells separately from row-covered ones —
# "covered by a sibling builder" must never become a way to make anything green. A reason naming a site
# no method occupies is reported STALE rather than silently ignored, so deleting the method it excused
# surfaces the excuse instead of leaving it to rot.
#
# The legitimate classes, and nothing else belongs here:
#
#   :unreachable  — the method cannot be called with any argument the package admits, so no row exists
#                   that could drive it (a fallback whose sole purpose is to throw a better error).
#   :not-a-value  — the method returns no value an oracle can compare: a setter, a printer, a
#                   constructor of an opaque handle.
#   :device-only  — the method dispatches on a device backend and a CPU survey cannot reach it. The
#                   GPU parity suite is where it is checked, and that is a different instrument.

# site => (class, how many methods this reason closes, text).
#
# THE COUNT IS LOAD-BEARING, and it is here because the ledger's own probe 4 caught its absence: a
# reason keyed by definition site silently closed FOUR methods, because four codegen methods share
# that site. Silently closing a group is the "covered by a sibling builder" escape the design warns
# about, so the number of methods a reason closes must be DECLARED and is verified against the method
# table. A reason whose declared count is wrong is reported rather than applied.
const LEDGER_REASONS = Dict{String, Tuple{Symbol, Int, String}}(
  # Error fallbacks. Both exist to REFUSE a call and say why, so there is no value for an oracle to
  # compare; the refusal itself is asserted by the survey's domain-rejection lane, not here.
  "Reductions.jl:1496" => (:not_a_value, 1,
    "`extrema(::AbstractFiberSection)` throws: an order statistic above R = 0 is ill-posed until a fiber map names what is ordered"),
  "Reductions.jl:655" => (:not_a_value, 1,
    "`var` on a non-scalar section throws: the fiber-preserving variance is basis-dependent and the package declines it"),
  # An ambiguity resolver the field layer cannot be driven through. A destination whose tensor order
  # matches the operands dispatches to the more specific method; one whose order does not is REFUSED
  # by the compatibility check, so no call both reaches this method and returns a value.
  "FieldAlgebra.jl:767" => (:unreachable, 1,
    "exists to resolve dispatch ambiguity; a matching destination reaches the more specific method and a mismatched one is refused"),
)


"""
    ledger_reason(cell) -> Union{Nothing, String}

The recorded reason this method cannot have a value row, or `nothing` if none is recorded — in which
case an uncovered method is a finding.
"""
function ledger_reason(cell)
  entry = get(LEDGER_REASONS, cell.site, nothing)
  entry === nothing && return nothing
  return string(entry[1], " (closes ", entry[2], "): ", entry[3])
end


"""
    ledger_miscounted_reasons(cells) -> Vector{String}

Reasons whose declared method count disagrees with how many methods actually sit at that site. A
reason that closes more than it says is the escape hatch widening itself, so the disagreement is
reported and the reason is not honoured.
"""
function ledger_miscounted_reasons(cells)
  actual = Dict{String, Int}()
  for cell in cells
    actual[cell.site] = get(actual, cell.site, 0) + 1
  end
  bad = String[]
  for (site, entry) in LEDGER_REASONS
    haskey(actual, site) || continue
    actual[site] == entry[2] || push!(bad, string(site, " declares ", entry[2], ", closes ", actual[site]))
  end
  return sort(bad)
end


"""
    ledger_stale_reasons(cells) -> Vector{String}

Recorded reasons whose site no longer carries a package method. A stale reason is reported rather than
ignored: the excuse outliving the method it excused is exactly how an escape hatch becomes permanent.
"""
function ledger_stale_reasons(cells)
  live = Set(cell.site for cell in cells)
  return sort([site for site in keys(LEDGER_REASONS) if !(site in live)])
end
