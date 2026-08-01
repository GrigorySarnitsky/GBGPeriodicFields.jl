# The sequence axis: properties that only exist across SEVERAL calls.
#
# Every other lane makes one call and asks whether the answer is right. That is blind to a whole class
# by construction, and the package's own history says so:
#
#   invariant 11 exists because the inverse real transform CONSUMES its spectral input as scratch. A
#   single call cannot see it — the result is correct either way. It surfaces only when the source is
#   used afterwards, and it is backend-divergent (FFTW destroys, rocFFT preserves), so the contract is
#   "never rely on it" rather than "it is destroyed".
#
#   invariant 13 exists because of an n-step defect. A per-call device temporary escapes Julia's GC,
#   which triggers on HOST pressure and is blind to the device buffer a dead array owns, so one call
#   allocates fine and a hot loop wedges the card (decisions 24-26). Measuring one call is exactly the
#   measurement that misses it.
#
# So this lane runs sequences: a plan used repeatedly, an operation applied n times, a round trip
# cycled, and an in-place loop watched for accumulation.

using GBGPeriodicFields
using Statistics
using LinearAlgebra

# Long enough that a per-step leak is unambiguous against the one-off cost of the first iteration, and
# short enough to cross every configuration.
const SEQUENCE_STEPS = 64

# A named fiber map, so the loop measurement is not charged for a fresh closure type each call.
_double_fiber(fiber) = 2 * fiber


"""
    loop_allocated(operation!, steps, arguments...) -> Int

Bytes allocated by running `operation!(arguments...)` `steps` times.

A FUNCTION BARRIER, and that is the whole point. Measuring the loop inline inside the lane charged
every operation a uniform ~144 bytes per step — the enclosing scope is type-unstable (its workbench is
a NamedTuple carrying a type parameter), so its locals are boxed and each access allocates. The
package was reporting the harness. Passing the arguments through a specialized call makes their types
concrete at the loop, so what is measured is the operation.
"""
@noinline function _loop_bytes(operation!::F, steps::Int, arguments::Vararg{Any, N}) where {F, N}
  operation!(arguments...)                     # warm up: the first call compiles
  return @allocated for _ in 1:steps
    operation!(arguments...)
  end
end

# A call of the same arity and argument types that does nothing, so the loop's own per-step cost can be
# measured and removed.
@noinline _no_operation(arguments::Vararg{Any, N}) where {N} = nothing

# The harness has a per-step cost of its own — splatting a heterogeneous argument tuple through a
# `Vararg` call is not free — and it is the same order as the thing being detected. Subtracting a
# control of identical shape leaves what the OPERATION allocates. Without it, four operations the
# gate's own audit pins at zero reported 128-432 bytes per step.
function loop_allocated(operation!::F, steps::Int, arguments...) where {F}
  measured = _loop_bytes(operation!, steps, arguments...)
  control = _loop_bytes(_no_operation, steps, arguments...)
  return max(0, measured - control)
end


"""
    run_sequence_lane(configs) -> (failures, cells)

Check the properties that need more than one call: plan reuse, repeated application, round-trip
cycling, and allocation across an n-step loop.
"""
function run_sequence_lane(configs)
  println("═"^100)
  println("LANE: sequences — the properties a single call cannot exhibit")
  println("      invariant 11 (a `!` transform consumes its source) and invariant 13 (a hot loop")
  println("      accumulates what one call does not) are both sequence properties")
  println("═"^100)

  failures = String[]
  cells = 0
  record!(message) = Base.push!(failures, message)

  for config in configs
    b = _bench(config)
    rtol = _tolerance(b.T)
    m, z = b.multipliers, b.z

    # ── a plan survives reuse ──────────────────────────────────────────────────────────────────
    # A plan whose construction or first use overwrote its own arrays would give a different answer the
    # second time. The transforms are the package's only stateful objects, so this is where it matters.
    cells += 1
    first_pass = copy(field_data(to_spectral(b.s, b.plans0)))
    second_pass = copy(field_data(to_spectral(b.s, b.plans0)))
    # `isequal`, not `==`. This is the NaN class `checks.jl` fixed twice and `selfcheck.jl` locks in on
    # both of its branches; `sequences.jl` reimplemented the same comparison and never received it, so a
    # reproducible NaN would be misreported as irreproducibility.
    isequal(first_pass, second_pass) ||
      record!("to_spectral is not reproducible when its plan is reused [$(config.name)]")

    cells += 1
    physical_first = copy(field_data(to_physical(b.sh, b.plans0)))
    physical_second = copy(field_data(to_physical(b.sh, b.plans0)))
    isequal(physical_first, physical_second) ||
      record!("to_physical is not reproducible when its plan is reused [$(config.name)]")

    # ── the allocating transform preserves its source across repeated use ──────────────────────
    # This is the half of invariant 11 that IS an assertion. The in-place form's consumption of its
    # source is backend-divergent and therefore contractual rather than testable, but the allocating
    # form promises preservation unconditionally, and a caller relies on it to keep a spectral field
    # across a round trip.
    cells += 1
    pristine = copy(field_data(b.sh))
    for _ in 1:4
      to_physical(b.sh, b.plans0)
    end
    isequal(field_data(b.sh), pristine) ||
      record!("the allocating to_physical modified its source across repeated calls [$(config.name)]")

    # ── repeated application of an idempotent operation ────────────────────────────────────────
    # ℙ and a sharp cutoff are projections: applying them n times must equal applying them once. Drift
    # here is an accumulation defect that a single call and a double call both miss.
    cells += 1
    projected = helmholtz_projection(b.uh, m)
    repeated = projected
    for _ in 2:8
      repeated = helmholtz_projection(repeated, m)
    end
    isapprox(field_data(repeated), field_data(projected); rtol = rtol) ||
      record!("helmholtz_projection drifts under repeated application [$(config.name)]")

    cells += 1
    kernel = spectral_cutoff(z, m, b.T(3))
    filtered = convolve(b.sh, kernel)
    cycled = filtered
    for _ in 2:8
      cycled = convolve(cycled, kernel)
    end
    isapprox(field_data(cycled), field_data(filtered); rtol = rtol) ||
      record!("a sharp cutoff drifts under repeated application [$(config.name)]")

    # ── a round trip cycled n times ────────────────────────────────────────────────────────────
    # One round trip is checked by the relations lane. Cycling it accumulates whatever error a single
    # pass hides, which is the regime a solver actually runs in.
    cells += 1
    cycling = b.s
    for _ in 1:16
      cycling = to_physical(to_spectral(cycling, b.plans0), b.plans0)
    end
    isapprox(field_data(cycling), field_data(b.s); rtol = sqrt(eps(b.T)) * 100) ||
      record!("16 transform round trips drift beyond tolerance [$(config.name)]")

    # ── allocation across an n-step loop ───────────────────────────────────────────────────────
    # The measurement invariant 13 is actually about. Each operation is run once to compile and settle,
    # then the loop is measured: a per-call temporary shows up as bytes proportional to the step count,
    # which a single-call measurement reports as zero.
    u, v, A, uh, vh, sh, half = b.u, b.v, b.A, b.uh, b.vh, b.sh, b.T(1) / 2
    plans1, decay = b.plans1, -b.T(1) / 10
    measurements = (("add!",                  loop_allocated(add!, SEQUENCE_STEPS, u, u, v)),
                    ("combine!",              loop_allocated(combine!, SEQUENCE_STEPS, u, half, u, half, v)),
                    ("mul!",                  loop_allocated(mul!, SEQUENCE_STEPS, v, A, u)),
                    ("map!",                  loop_allocated(map!, SEQUENCE_STEPS, _double_fiber, u, u)),
                    ("laplacian!",            loop_allocated(laplacian!, SEQUENCE_STEPS, vh, uh, m)),
                    ("curl!",                 loop_allocated(curl!, SEQUENCE_STEPS, vh, uh, m)),
                    ("helmholtz_projection!", loop_allocated(helmholtz_projection!, SEQUENCE_STEPS, vh, uh, m)),
                    ("convolve!",             loop_allocated(convolve!, SEQUENCE_STEPS, vh, uh, kernel)),
                    ("exponential_convolve!", loop_allocated(exponential_convolve!, SEQUENCE_STEPS, vh, uh, m, decay)),
                    ("to_spectral!",          loop_allocated(to_spectral!, SEQUENCE_STEPS, uh, u, plans1)))
    # The bound is a FRACTION OF A FIELD, because that is what invariant 13 is about: a per-call
    # device temporary that escapes the GC and grows the pool every step. Measured at top level the way
    # the gate's own audit does it, `laplacian!` and `exponential_convolve!` allocate 144 bytes per
    # call and `convolve!` 128 — small fixed constants, not scratch, and the gate passes them. A bound
    # of a few kilobytes total would have reported all three as leaks; the property is that nothing
    # FIELD-SIZED is allocated per step, and a field here is tens of kilobytes.
    field_bytes = sizeof(eltype(field_data(b.u))) * length(field_data(b.u))
    per_step_bound = max(1024, field_bytes ÷ 8)
    for (name, loop_bytes) in measurements
      cells += 1
      per_step = div(loop_bytes, SEQUENCE_STEPS)
      per_step < per_step_bound ||
        record!("$(name) allocated ~$(per_step) bytes per step over $(SEQUENCE_STEPS) steps, " *
                "against a field of $(field_bytes) bytes [$(config.name)]")
    end
    if config === first(configs)
      println("\n  per-step allocation over ", SEQUENCE_STEPS, " steps (bound ", per_step_bound,
              " B/step, a field is ", field_bytes, " B):")
      for (name, loop_bytes) in measurements
        println("      ", rpad(name, 24), lpad(div(loop_bytes, SEQUENCE_STEPS), 6), " B/step")
      end
    end

    # ── an in-place loop computes what the same steps compute one at a time ────────────────────
    # An operation whose destination is also its source is applied repeatedly here, which is the shape
    # a solver's state update has. The reference accumulates the same steps through fresh allocations.
    # A FRESH fixture. The allocation loops above run `map!(_double_fiber, u, u)` sixty-five times,
    # scaling `u` by 2^65 ≈ 1.8e19 — at which magnitude one ulp is 2048 and the `8·v` this check adds
    # (|v| ≤ 0.75) vanishes entirely. Both sides then collapse onto the same number and the check passes
    # whatever `add!` does. Every per-step allocation figure after `map!` was also measured on that
    # unintended fixture.
    fresh = _bench(config)
    cells += 1
    accumulating = copyto!(field_data(similar_field(fresh.u, Val(1))), field_data(fresh.u))
    looped = similar_field(fresh.u, Val(1))
    copyto!(field_data(looped), field_data(fresh.u))
    for _ in 1:8
      add!(looped, looped, fresh.v)
    end
    expected = accumulating .+ 8 .* field_data(fresh.v)
    isapprox(field_data(looped), expected; rtol = rtol) ||
      record!("an 8-step accumulate into its own destination diverges from the same steps [$(config.name)]")
  end

  println("\n  ", cells, " sequence checks over ", length(configs), " configurations · ",
          SEQUENCE_STEPS, " steps per allocation loop")
  if isempty(failures)
    println("  every sequence property holds")
  else
    println("\n  A SEQUENCE PROPERTY FAILS — ", length(failures), " cells:")
    for f in unique(failures); println("      ", f); end
  end
  return (length(failures), cells)
end
