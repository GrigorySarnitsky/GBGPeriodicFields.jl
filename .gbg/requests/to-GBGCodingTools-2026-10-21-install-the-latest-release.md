# To GBGCodingTools: a fleet package installed by its URL gets the development head, not its latest release

Status: approved by the owner on 2026-10-21, sent to the GBGCodingTools session the same day. The
owner's words: it is the tool's job to coordinate the fleet and its releases.

## What happens

GBGPeriodicFields went public and was released as v0.1.0 on 2026-10-21 through `gbg release`, and is
not registered in General, by the owner's ruling. Julia's package manager knows "latest release" only
through a registry, so a user who writes

```julia
Pkg.add(url = "https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl")
```

tracks the repository's default branch: today the head of `master`, the development branch, which may
be broken between releases, and `Pkg.update()` follows it there. Only an explicit
`rev = "v0.1.0"` gives the release. GBGHomogeneousTurbulence installs PF by URL and is next to go
public, so the same holds for it and for every fleet package after it, and none of them can state a
version bound on another, a bound being something only a registry resolves.

The documentation is already right and needs nothing: Documenter deploys on every tag, and the site's
root redirects to `stable/`, built from the latest tag, with the master build at `dev/`.

## What the owner wants

The plain installation command gives the latest release, for every package of the fleet, and moves
only between releases on `Pkg.update()`.

## The routes PF sees, for the tool to choose between

1. **Register in General.** `Pkg.add("GBGPeriodicFields")` gives the latest release, with compat
   bounds between packages. Against the owner's 2026-10 ruling that a tagged public version is the
   whole release, so a change of that ruling.
2. **A fleet registry** maintained by the tool: a small public git repository of the fleet's releases,
   in the format `LocalRegistry.jl` writes, updated by `gbg release` as it tags. A user adds it once,
   `Pkg.Registry.add(url = "…")`, and from then on `Pkg.add("GBGPeriodicFields")` gives the latest
   release; the fleet's packages can state compat bounds on one another. PF's recommendation: the
   Julia-standard release semantics without General, and the only route besides General that gives
   inter-package bounds.
3. **A release branch as the repository's default**, moved by `gbg release` to each tag, with
   development on `master`. A bare `Pkg.add(url = …)` then installs the latest release, with no
   registry; but no inter-package bounds, and unusual for a Julia package.

Each route except the first makes `gbg release` do one more thing at the tag, which is why this is the
tool's rather than PF's.

## Until then

PF's README and documentation should give the install line with `rev = "v0.1.0"`, moved at each release.
That is PF's to do, and it waits for the owner.
