# The package's true public surface (decision 55, second pass).
#
# Every completeness guard needs the same thing: the set of operations a user can call. The obvious
# derivation, `names(GBGPeriodicFields)`, is WRONG, and wrong in a way that hides the newest work.
# The package extends `Base` and `Statistics` generics — `map`/`map!` (decision 48),
# `mean`/`std`/`var`/`cov` (49), `maximum`/`minimum`/`extrema` — and deliberately does not re-export
# them, since re-exporting another package's bindings is avoided. So `names()` cannot see them, and
# three guards built on it were each blind to nine public operations, decisions 48 and 49 among them.
#
# Derive from ownership instead: a function is part of the surface when a package module owns at
# least one of its methods. That reaches an extension of an external generic exactly as it reaches a
# generic the package declares itself.

const PACKAGE_MODULES = Set([
  GBGPeriodicFields.FiberSections, GBGPeriodicFields.Fields, GBGPeriodicFields.FieldAlgebra,
  GBGPeriodicFields.DifferentialOperators, GBGPeriodicFields.Convolution, GBGPeriodicFields.Points,
  GBGPeriodicFields.Interpolation, GBGPeriodicFields.Reductions,
])


"""
    package_operations() -> Set{Symbol}

Every function the package owns methods of, whether it declares the generic or extends an external
one. This is the domain every completeness guard must cover.
"""
function package_operations()
  # The umbrella's own public surface.
  found = Set(n for n in names(GBGPeriodicFields)
              if isdefined(GBGPeriodicFields, n) && getfield(GBGPeriodicFields, n) isa Function)
  # Plus every EXTERNAL generic the package extends. This must be derived, and deriving it from
  # module NAMESPACES is not enough: `Base.inv(kernel::SeparableKernel) = …` (decision 50) defines a
  # method under a qualified name, so `inv` never becomes a binding in `Convolution` and no scan of
  # `names(Convolution)` can reach it. Walk the loaded modules instead and ask each function whether
  # a package module owns one of its methods — the only question whose answer cannot depend on how
  # the definition was spelled.
  for mod in Base.loaded_modules_array()
    for name in names(mod; all = true, imported = true)
      isdefined(mod, name) || continue
      f = try getfield(mod, name) catch; continue end
      f isa Function || continue
      # `kwcall` is Julia's keyword-argument dispatch artifact, not an operation anyone calls.
      nameof(f) === :kwcall && continue
      any(m -> m.module in PACKAGE_MODULES, methods(f)) && push!(found, nameof(f))
    end
  end
  return found
end


"Operations whose name ends in `!` — the in-place surface the two ledgers must cover."
inplace_operations() = Set(n for n in package_operations() if endswith(String(n), "!"))

"Operations that return a value — the surface the oracle registry must classify."
value_operations() = Set(n for n in package_operations() if !endswith(String(n), "!"))


"""
    all_package_functions() -> Set{Symbol}

Every function name a package module owns methods of, internal helpers included. The public surface
is what a guard must COVER; this wider set is what a guard's own bookkeeping may legitimately NAME —
an element-traffic row may audit an internal kernel directly.
"""
function all_package_functions()
  found = Set{Symbol}()
  for mod in PACKAGE_MODULES, name in names(mod; all = true, imported = true)
    isdefined(mod, name) || continue
    f = getfield(mod, name)
    f isa Function || continue
    any(m -> m.module in PACKAGE_MODULES, methods(f)) && push!(found, name)
  end
  return union(found, package_operations())
end
