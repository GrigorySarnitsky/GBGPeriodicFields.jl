"""
    FiberSections

Base-agnostic core of the package's fiber-bundle model.

A field (a section over a `Grid3D`) and a collection of off-grid point-values (a section over a
`PointSet`) are both *sections of a tensor bundle over a base* (`docs/ARCHITECTURE.md` §2). This
module owns the part of the design that does not depend on the base — currently the
[`AbstractFiberSection`](@ref) supertype — so that the fiberwise (vertical) algebra, written once,
can serve both field and point-value sections.
"""
module FiberSections


export AbstractFiberSection


"""
    AbstractFiberSection{T, R}

Supertype of every section of the package's tensor bundle: fields (sections over a `Grid3D`,
in physical-space or spectral representation) and point-values (sections over a `PointSet`).

Here `T<:AbstractFloat` is the real scalar type and `R` the tensor order (`0` scalar, `1` vector,
`2` second-order tensor, and so on). The fiberwise algebra is rooted at this supertype because it
is base-independent — the same operation on the same fiber type regardless of whether the base is
a structured grid or an unstructured point set (`docs/ARCHITECTURE.md` §2).
"""
abstract type AbstractFiberSection{T<:AbstractFloat, R} end


end # module FiberSections
