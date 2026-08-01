# The predicates and comparisons every lane shares — defined ONCE.
#
# WHY THIS FILE EXISTS. Five adversarial rounds converged on a single generator of defects: a correct
# fix applied to one instance and not to its siblings. The exception-type check reached three of four
# rejection filters; `isequal` reached two of three reproducibility comparisons; the extension-modules
# fix reached two of three module lists; returning the exception type instead of a sentinel reached one
# of two comparison helpers. Every one was found by an adversary, and each fix seeded the next round.
#
# Finding siblings faster is not the answer — removing the possibility of a sibling is. A pattern that
# exists once cannot be half-fixed, so each definition below replaces a family of copies, and a lane
# that needs the behaviour calls it rather than restating it.

using GBGPeriodicFields


"""
    is_domain_refusal(exception) -> Bool

Whether an exception is the package REFUSING an argument, as opposed to the harness failing to make
the call.

The distinction is the whole point: a bare `catch` counts a `MethodError` from a renamed keyword, a
wrong arity in the test, or a typo as a correct refusal — so a deleted validation stays green as long
as the call fails for any other reason. This set was written out separately at four sites and drifted
at three of them.
"""
is_domain_refusal(exception) =
  exception isa ArgumentError || exception isa DimensionMismatch ||
  exception isa InexactError || exception isa DomainError

"""
    is_domain_refusal_or_bounds(exception) -> Bool

As [`is_domain_refusal`](@ref), and also `BoundsError` — for the point transfer, where a coordinate
outside the box legitimately reaches an out-of-range stencil index.
"""
is_domain_refusal_or_bounds(exception) = is_domain_refusal(exception) || exception isa BoundsError


"""
    reproduces(a, b) -> Bool

Whether two results of the same computation are identical, NaN included.

`==` is wrong here and was wrong at three sites before this: `NaN != NaN`, so a call that legitimately
produces a NaN twice reads as irreproducible. Every bitwise reproducibility comparison in the suite —
thread invariance, plan reuse, aliasing, source preservation — goes through this.
"""
reproduces(a, b) = isequal(a, b)


"""
    comparison_outcome(body) -> Bool, or the exception type

Run a comparison, returning its verdict or the type of whatever it threw.

A bare sentinel loses the diagnosis, and returning one from a helper while its sibling returns the
type is how the two drifted apart. Every extracted comparison step returns this shape.
"""
function comparison_outcome(body)
  return try
    body()
  catch exception
    nameof(typeof(exception))
  end
end


"""
    package_modules(; extensions = true) -> Tuple

The package's own modules, optionally including the loaded weak-dependency extensions.

Three module lists existed independently; the extension-modules fix reached two of them. A lane that
needs the list calls this.
"""
function package_modules(; extensions::Bool = true)
  core = (GBGPeriodicFields.FiberSections, GBGPeriodicFields.Fields, GBGPeriodicFields.FieldAlgebra,
          GBGPeriodicFields.DifferentialOperators, GBGPeriodicFields.Convolution,
          GBGPeriodicFields.Points, GBGPeriodicFields.Interpolation, GBGPeriodicFields.Reductions)
  extensions || return core
  return isdefined(Main, :EXTENSION_MODULES) ? (core..., Main.EXTENSION_MODULES...) : core
end
